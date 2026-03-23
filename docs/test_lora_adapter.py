"""
test_lora_adapter.py
────────────────────
Smoke-test the fine-tuned BLA model (LoRA adapter or merged full model).

Loading strategy mirrors chatbot.py exactly:
  1. Try the merged full model   (Gemma3_BLA_full/)
  2. Fall back to base + adapter (lora_adapter/)
  3. Fall back to base model only (no fine-tuning — for baseline comparison)

Test suite covers:
  • Dog bite — initial Tagalog question
  • Dog bite — English follow-up (owner refuses to pay)
  • VAWC     — initial complaint
  • Noise    — videoke complaint
  • Refusal  — out-of-scope (homicide case)
  • Refusal  — out-of-scope (annulment)
  • Mediation — what is Lupong Tagapamayapa

Usage:
    python test_lora_adapter.py                    # full test suite
    python test_lora_adapter.py --prompt "..."     # single custom prompt
    python test_lora_adapter.py --base-only        # compare against untuned base
    python test_lora_adapter.py --max-tokens 512   # longer responses
"""

import argparse
import os
import sys
import time
import textwrap
import torch
from typing import List, Tuple

# ─── Argument parsing ─────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="BLA LoRA adapter inference tester")
parser.add_argument("--prompt",     type=str, default=None,
                    help="Run a single custom prompt instead of the full test suite")
parser.add_argument("--base-only",  action="store_true",
                    help="Skip fine-tuned model and test untuned base for comparison")
parser.add_argument("--max-tokens", type=int, default=350,
                    help="Max new tokens per response (default: 350)")
parser.add_argument("--no-color",   action="store_true",
                    help="Disable ANSI colour output")
args = parser.parse_args()

# ─── Paths (same as chatbot.py) ───────────────────────────────────────────────
_HERE            = os.path.dirname(os.path.abspath(__file__))
_BLA_DIR         = os.path.join(_HERE, "backend", "app", "bla_model")
FULL_MODEL_DIR   = os.path.join(_BLA_DIR, "Gemma3_BLA_full")
LORA_ADAPTER_DIR = os.path.join(_BLA_DIR, "lora_adapter")
BASE_MODEL_ID    = "google/gemma-3-1b-it"

# ─── System prompt (must match chatbot.py and finetune_lora.py) ───────────────
SYSTEM_PROMPT = (
    "You are the official AI Legal Assistant of the Barangay Legal Aid (BLA) Application, "
    "serving residents of barangays in the Philippines. "
    "Your primary duty is to provide DETAILED, accurate, and actionable legal guidance "
    "on barangay matters, Filipino laws, and community services."
    "\n\nStrict Rules:"
    "\n1. ALWAYS give comprehensive, step-by-step answers. Never give one-line or vague replies."
    "\n2. Explain the FULL PROCESS — requirements, fees, offices to visit, timelines, and what to expect."
    "\n3. Cite relevant Philippine laws when appropriate (RA 7160, Katarungang Pambarangay, "
    "Civil Code, Revised Penal Code, etc.)."
    "\n4. Answer in the SAME LANGUAGE the user writes in — Filipino/Tagalog or English. "
    "If the user writes in Tagalog, respond FULLY in Tagalog."
    "\n5. Be empathetic and professional. Residents rely on you for real, practical legal help."
    "\n6. Never say 'I cannot help with legal matters' — that IS your purpose."
    "\n7. If asked about a document, complaint, or legal process, explain all steps completely."
)

# ─── Generation hyperparameters (same as chatbot.py) ─────────────────────────
GEN_KWARGS = dict(
    max_new_tokens=args.max_tokens,
    do_sample=True,
    temperature=0.3,
    top_p=0.9,
    repetition_penalty=1.15,
    use_cache=True,
)

# ─── Colour helpers ───────────────────────────────────────────────────────────
_C = not args.no_color and sys.stdout.isatty()

def _cyan(s):   return f"\033[96m{s}\033[0m"  if _C else s
def _green(s):  return f"\033[92m{s}\033[0m"  if _C else s
def _yellow(s): return f"\033[93m{s}\033[0m"  if _C else s
def _red(s):    return f"\033[91m{s}\033[0m"   if _C else s
def _bold(s):   return f"\033[1m{s}\033[0m"    if _C else s

# ─── Test suite definition ────────────────────────────────────────────────────
# Each entry: (label, prompt_text, expected_keywords, should_refuse)
#   expected_keywords — list of strings that SHOULD appear in the response
#   should_refuse     — True means the response should say it's out of scope
TEST_CASES = [
    (
        "Dog Bite — Initial (Tagalog)",
        "Kinagat ako ng aso ng aking kapitbahay kahapon. Masakit at may sugat ako. "
        "Ano ang dapat kong gawin? Pwede ba akong magreklamo sa barangay?",
        ["barangay", "RA 9482", "sumbong", "mediasyon", "ospital"],
        False,
    ),
    (
        "Dog Bite — Follow-up (owner refuses to pay)",
        "I already reported the dog bite to the barangay and we had a mediation "
        "hearing. But my neighbor refuses to pay my hospital bills worth P8,500. "
        "The barangay could not settle it. What do I do now?",
        ["Certification to File Action", "CFA", "court", "small claims", "RA 9482"],
        False,
    ),
    (
        "VAWC — Initial complaint",
        "My husband punched me last night and threatened to hurt our children. "
        "I am scared. What can the barangay do for me?",
        ["RA 9262", "Barangay Protection Order", "BPO", "Punong Barangay", "safety"],
        False,
    ),
    (
        "Noise Complaint — Videoke",
        "My neighbor plays videoke loudly every night until 2 AM. "
        "My kids cannot sleep. Can I file a complaint at the barangay?",
        ["Sumbong", "barangay", "mediation", "kasunduan", "noise"],
        False,
    ),
    (
        "Unpaid Debt — Initial",
        "I lent my neighbor P15,000 six months ago and she has not paid me back. "
        "Can I go to the barangay about this?",
        ["barangay", "mediation", "Lupon", "kasunduan", "small claims"],
        False,
    ),
    (
        "Barangay Clearance — How to apply",
        "How do I get a barangay clearance? What are the requirements?",
        ["barangay", "clearance", "ID", "fee", "Punong Barangay"],
        False,
    ),
    (
        "Mediation — What is Lupong Tagapamayapa",
        "What is the Lupong Tagapamayapa and how does it work?",
        ["Lupon", "RA 7160", "mediation", "kasunduan", "Pangkat"],
        False,
    ),
    (
        "Refusal — Homicide (out of scope)",
        "My brother was stabbed and killed by his neighbor. "
        "Can we file the murder case at the barangay?",
        ["outside", "jurisdiction", "prosecutor", "PNP", "court"],
        True,
    ),
    (
        "Refusal — Annulment (out of scope)",
        "I want to get an annulment from my husband. Can the barangay process this?",
        ["outside", "jurisdiction", "Regional Trial Court", "Family Court", "lawyer"],
        True,
    ),
    (
        "Refusal — Drug trafficking (out of scope)",
        "I think my neighbor is selling drugs. Can the barangay arrest him?",
        ["outside", "jurisdiction", "PNP", "PDEA", "barangay"],
        True,
    ),
]

# ─── Model loading ────────────────────────────────────────────────────────────
model      = None
tokenizer  = None
model_tag  = "unknown"

if args.base_only:
    print(_yellow("--base-only flag set: loading untuned base model for comparison."))
    from transformers import AutoTokenizer, AutoModelForCausalLM
    print(f"Loading base model {BASE_MODEL_ID}…")
    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_ID, trust_remote_code=True)
    model     = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL_ID,
        torch_dtype=torch.float16,
        device_map="auto",
        trust_remote_code=True,
    )
    model.eval()
    model_tag = "BASE (untuned)"

else:
    from transformers import AutoTokenizer, AutoModelForCausalLM
    from peft import PeftModel

    # Strategy 1 — merged full model (faster inference)
    full_config = os.path.join(FULL_MODEL_DIR, "config.json")
    if os.path.exists(full_config):
        print(_green(f"Strategy 1: Loading merged full model from {FULL_MODEL_DIR}…"))
        try:
            tokenizer = AutoTokenizer.from_pretrained(FULL_MODEL_DIR)
            model     = AutoModelForCausalLM.from_pretrained(
                FULL_MODEL_DIR,
                device_map="auto",
            )
            model.eval()
            model_tag = "MERGED FULL MODEL"
            print(_green("  Full model loaded successfully."))
        except Exception as e:
            print(_yellow(f"  Full model failed: {e}"))
            model = None

    # Strategy 2 — base + LoRA adapter
    if model is None and os.path.exists(LORA_ADAPTER_DIR):
        adapter_config = os.path.join(LORA_ADAPTER_DIR, "adapter_config.json")
        if os.path.exists(adapter_config):
            print(_yellow(f"Strategy 2: Loading base + LoRA adapter from {LORA_ADAPTER_DIR}…"))
            try:
                tokenizer = AutoTokenizer.from_pretrained(LORA_ADAPTER_DIR)
                base      = AutoModelForCausalLM.from_pretrained(
                    BASE_MODEL_ID,
                    torch_dtype=torch.float16,
                    device_map="auto",
                    trust_remote_code=True,
                )
                model     = PeftModel.from_pretrained(base, LORA_ADAPTER_DIR)
                model.eval()
                model_tag = "BASE + LORA ADAPTER"
                print(_green("  LoRA adapter loaded successfully."))
            except Exception as e:
                print(_red(f"  LoRA adapter failed: {e}"))
                model = None

    # Strategy 3 — base only (nothing fine-tuned yet)
    if model is None:
        print(_red("No fine-tuned model found. Loading untuned base for baseline output."))
        print(_red("  Run finetune_lora.py first to generate a trained adapter.\n"))
        tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_ID, trust_remote_code=True)
        model     = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID,
            torch_dtype=torch.float16,
            device_map="auto",
            trust_remote_code=True,
        )
        model.eval()
        model_tag = "BASE (untuned — no adapter found)"

tokenizer.pad_token    = tokenizer.eos_token
tokenizer.padding_side = "right"

device = next(model.parameters()).device
print(f"\n  Model  : {_bold(model_tag)}")
print(f"  Device : {device}\n")

# ─── Inference helper ─────────────────────────────────────────────────────────
def generate(user_query: str) -> Tuple[str, float]:
    """Run one inference call. Returns (response_text, latency_seconds)."""
    user_content = f"{SYSTEM_PROMPT}\n\n{user_query}"

    messages = [{"role": "user", "content": user_content}]
    prompt   = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )
    inputs = tokenizer(prompt, return_tensors="pt").to(device)
    prompt_len = inputs["input_ids"].shape[1]

    t0 = time.time()
    with torch.no_grad():
        output_ids = model.generate(
            **inputs,
            pad_token_id=tokenizer.eos_token_id,
            **GEN_KWARGS,
        )
    elapsed = time.time() - t0

    # Decode only the newly generated tokens (strip the prompt)
    new_ids  = output_ids[0][prompt_len:]
    response = tokenizer.decode(new_ids, skip_special_tokens=True).strip()
    return response, elapsed

# ─── Scoring helper ───────────────────────────────────────────────────────────
def score(response: str, keywords: List[str], should_refuse: bool) -> Tuple[int, int, List[str]]:
    """
    Returns (hits, total, missing_keywords).
    For refusal cases, checks that the response signals out-of-scope.
    """
    resp_lower = response.lower()
    hits   = 0
    missed = []
    for kw in keywords:
        if kw.lower() in resp_lower:
            hits += 1
        else:
            missed.append(kw)

    if should_refuse:
        # Refusal should NOT contain a structured barangay procedure
        if "step-by-step barangay procedure" in resp_lower:
            missed.append("[should NOT contain barangay procedure steps]")
        else:
            hits += 1  # bonus hit for correctly refusing

    return hits, len(keywords) + (1 if should_refuse else 0), missed

# ─── Run tests ────────────────────────────────────────────────────────────────
WIDTH = 78

def run_suite(test_cases):
    results = []
    for i, (label, prompt, keywords, should_refuse) in enumerate(test_cases, 1):
        print("─" * WIDTH)
        print(_bold(f"[{i}/{len(test_cases)}] {label}"))
        print(_cyan(f"  Q: {textwrap.shorten(prompt, width=WIDTH-5, placeholder='…')}"))

        response, latency = generate(prompt)

        # Word-wrap the response at 76 chars
        wrapped = textwrap.fill(response, width=WIDTH - 4,
                                initial_indent="  ", subsequent_indent="  ")
        print(f"\n{_yellow('Response:')}\n{wrapped}\n")

        hits, total, missed = score(response, keywords, should_refuse)
        pct    = hits / total * 100 if total else 0
        status = _green("PASS") if pct >= 60 else _red("WARN")

        print(f"  {status}  Keywords: {hits}/{total} ({pct:.0f}%)  |  "
              f"Latency: {latency:.1f}s")
        if missed:
            print(_red(f"  Missing: {', '.join(missed)}"))

        results.append((label, pct, latency))
        print()

    return results


def run_single(prompt: str):
    print("─" * WIDTH)
    print(_bold("Custom prompt:"))
    print(_cyan(f"  {prompt}\n"))
    response, latency = generate(prompt)
    wrapped = textwrap.fill(response, width=WIDTH - 4,
                            initial_indent="  ", subsequent_indent="  ")
    print(f"{_yellow('Response:')}\n{wrapped}")
    print(f"\n  Latency: {latency:.1f}s\n")


# ─── Entry point ──────────────────────────────────────────────────────────────
print("=" * WIDTH)
print(_bold(f"  BLA LoRA Adapter — Inference Test  [{model_tag}]"))
print("=" * WIDTH + "\n")

if args.prompt:
    run_single(args.prompt)
else:
    results = run_suite(TEST_CASES)

    # ── Summary table ────────────────────────────────────────────────────────
    print("=" * WIDTH)
    print(_bold("  SUMMARY"))
    print("=" * WIDTH)
    total_pct = 0
    for label, pct, latency in results:
        bar    = ("█" * int(pct // 10)).ljust(10)
        status = _green("PASS") if pct >= 60 else _red("WARN")
        print(f"  {status}  [{bar}] {pct:>5.1f}%  {latency:>5.1f}s  {label}")
        total_pct += pct

    avg_pct = total_pct / len(results)
    avg_lat = sum(r[2] for r in results) / len(results)
    print("─" * WIDTH)
    print(f"  Overall keyword coverage : {_bold(f'{avg_pct:.1f}%')}")
    print(f"  Average latency          : {avg_lat:.1f}s per response")
    print()

    if avg_pct < 50:
        print(_red("  Recommendation: coverage is low."))
        print(_red("  • Try training for more epochs (--epochs 8)."))
        print(_red("  • Check that SYSTEM_PROMPT in this file matches finetune_lora.py."))
        print(_red("  • Verify the adapter path is correct.\n"))
    elif avg_pct < 75:
        print(_yellow("  Recommendation: decent coverage but room to improve."))
        print(_yellow("  • Add more diverse training samples (aim for 100+)."))
        print(_yellow("  • Try r=32 in LoRA config for more capacity.\n"))
    else:
        print(_green("  Model looks good! Deploy to chatbot.py.\n"))
