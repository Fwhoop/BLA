"""
chatbot.py — BLA (Barangay Legal Aid) local-model inference engine.

Loads the fine-tuned Gemma-3 model once at startup from the local bla_model
directory.  No Hugging Face online calls are ever made.

Exported symbols used by routers/chat.py:
  - chat_response(sender, message) -> dict
  - generate_chat_response(user_input, history)  [backward-compatible]
  - load_faq_data() -> dict | None
"""

import os
import re
import json
import logging
import concurrent.futures as _cf
from typing import Optional, List, Dict, Tuple

# ── Force fully-offline mode BEFORE any HF / transformers imports ─────────────
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_DATASETS_OFFLINE", "1")

logger = logging.getLogger(__name__)

# ── Path resolution ───────────────────────────────────────────────────────────
# Local dev  → exact Windows path the developer provided.
# Railway    → ./bla_model/ next to this file (copy it into the Docker image).
_BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
_EXACT_PATH  = r"D:\Capstone BLA\BLA\BLA\barangay_legal_aid\backend\app\bla_model"
_REL_PATH    = os.path.join(_BASE_DIR, "bla_model")
MODEL_DIR    = _EXACT_PATH if os.path.exists(_EXACT_PATH) else _REL_PATH

# Knowledge-base JSON bundled with the backend image.
_JSON_FILE   = os.path.join(os.path.dirname(_BASE_DIR), "barangay_law_flutter.json")

logger.info(f"[STARTUP] bla_model path → {MODEL_DIR}")
logger.info(f"[STARTUP] FAQ JSON path  → {_JSON_FILE}")

# ── Runtime knobs (set via Railway env vars) ──────────────────────────────────
_LOAD_MODEL         = os.environ.get("LOAD_MODEL", "true").lower() != "false"
_GENERATION_TIMEOUT = int(os.environ.get("GENERATION_TIMEOUT", "45"))   # seconds

# ── System prompt ─────────────────────────────────────────────────────────────
_SYSTEM_PROMPT = """\
You are a Philippine Barangay Legal Advisory AI Assistant (BLA).

ROLE: Provide structured legal guidance strictly limited to barangay-level
jurisdiction under Philippine law.

SCOPE — answer only about:
• Barangay disputes and the Katarungang Pambarangay process (RA 7160)
• Mediation, conciliation, and amicable settlement
• Barangay clearance and document requests (clearance, residency, indigency,
  good moral character)
• Minor civil disputes: debt, boundary, noise, slander, trespass
• RA 9262 (VAWC) — barangay protection order level only
• RA 9482 (Anti-Rabies Act)
• Rights of complainant and respondent in barangay cases

If a topic is outside barangay jurisdiction, respond:
"This matter is outside barangay jurisdiction and requires proper legal or
professional consultation."

RESPONSE STRUCTURE (always follow):
1. Brief acknowledgment
2. Legal basis — cite the correct Philippine law
3. Rights of the complainant
4. Step-by-step barangay procedure
5. Possible outcomes
6. What to prepare

RULES:
• Do NOT fabricate article numbers or invent legal penalties
• Keep a bilingual tone (English + Filipino when natural)
• Use structured headings
• Never contradict earlier statements unless correcting clearly\
"""

# ── Model globals ─────────────────────────────────────────────────────────────
_tokenizer    = None
_model        = None
_model_loaded = False
_device       = "cpu"

# Single-worker pool so only one generation runs at a time (avoids OOM).
_executor = _cf.ThreadPoolExecutor(max_workers=1, thread_name_prefix="bla_gen")


# ── Model loading ─────────────────────────────────────────────────────────────
def _load_model() -> None:
    """Load the BLA model once at startup. Called in a background thread."""
    global _tokenizer, _model, _model_loaded, _device

    if not _LOAD_MODEL:
        logger.info("[STARTUP] LOAD_MODEL=false — skipping model load (FAQ-only mode).")
        return

    _full_dir    = os.path.join(MODEL_DIR, "Gemma3_BLA_full")
    _adapter_cfg = os.path.join(MODEL_DIR, "adapter_config.json")
    if not (os.path.isdir(_full_dir) or os.path.exists(_adapter_cfg)):
        logger.warning(
            f"[STARTUP] No loadable model found at {MODEL_DIR}. "
            "Running in FAQ-fallback mode."
        )
        return

    try:
        import torch
        from transformers import AutoTokenizer, AutoModelForCausalLM

        _device = "cuda" if torch.cuda.is_available() else "cpu"
        logger.info(f"[STARTUP] device={_device}")

        # ── Strategy 1: full merged model ─────────────────────────────────────
        _full_dir = os.path.join(MODEL_DIR, "Gemma3_BLA_full")
        if os.path.isdir(_full_dir) and os.path.exists(
            os.path.join(_full_dir, "config.json")
        ):
            logger.info(f"[STARTUP] Loading full model from {_full_dir} …")
            _tokenizer = AutoTokenizer.from_pretrained(
                _full_dir, local_files_only=True
            )
            _model = AutoModelForCausalLM.from_pretrained(
                _full_dir,
                device_map="auto" if _device == "cuda" else None,
                torch_dtype=torch.float16 if _device == "cuda" else torch.float32,
                local_files_only=True,
            )
            if _device == "cpu":
                _model = _model.to("cpu")
            _model.eval()
            _model_loaded = True
            logger.info("[STARTUP] Full model loaded successfully.")
            return

        # ── Strategy 2: LoRA adapter + base model from local HF cache ─────────
        _adapter_cfg = os.path.join(MODEL_DIR, "adapter_config.json")
        if os.path.exists(_adapter_cfg):
            try:
                from peft import PeftModel

                with open(_adapter_cfg) as _f:
                    _cfg = json.load(_f)
                _base_id = _cfg.get("base_model_name_or_path", "google/gemma-3-1b-it")

                logger.info(
                    f"[STARTUP] Loading LoRA adapter from {MODEL_DIR} "
                    f"(base={_base_id}) …"
                )
                _tokenizer = AutoTokenizer.from_pretrained(
                    MODEL_DIR, local_files_only=True
                )
                _base = AutoModelForCausalLM.from_pretrained(
                    _base_id,
                    device_map="auto" if _device == "cuda" else None,
                    torch_dtype=torch.float16 if _device == "cuda" else torch.float32,
                    local_files_only=True,
                )
                _model = PeftModel.from_pretrained(
                    _base, MODEL_DIR, local_files_only=True
                )
                if _device == "cpu":
                    _model = _model.to("cpu")
                _model.eval()
                _model_loaded = True
                logger.info("[STARTUP] LoRA model loaded successfully.")
                return

            except Exception as _e:
                logger.error(f"[STARTUP] LoRA load failed: {_e}", exc_info=True)

        logger.warning(
            f"[STARTUP] No loadable model found at {MODEL_DIR}. "
            "Running in FAQ-fallback mode."
        )

    except ImportError as _e:
        logger.warning(f"[STARTUP] ML libraries unavailable ({_e}). FAQ-fallback mode.")
    except Exception as _e:
        logger.error(f"[STARTUP] Unexpected model load error: {_e}", exc_info=True)


# ── FAQ / knowledge base ──────────────────────────────────────────────────────
_faq_cache: Optional[dict] = None


def load_faq_data() -> Optional[dict]:
    """Load barangay_law_flutter.json once and cache it. Used by /chats/faq."""
    global _faq_cache
    if _faq_cache is not None:
        return _faq_cache
    if not os.path.exists(_JSON_FILE):
        logger.warning(f"FAQ file not found: {_JSON_FILE}")
        return None
    try:
        with open(_JSON_FILE, "r", encoding="utf-8") as _f:
            _faq_cache = json.load(_f)
        logger.info(
            f"[STARTUP] FAQ loaded — {len(_faq_cache.get('categories', []))} categories"
        )
    except Exception as _e:
        logger.error(f"FAQ load error: {_e}")
    return _faq_cache


def _faq_search(query: str) -> Optional[str]:
    """Simple keyword search over the FAQ JSON. Returns best answer or None."""
    data = load_faq_data()
    if not data:
        return None

    q_lower = re.sub(r"[^\w\s]", "", query.lower())
    q_words  = set(q_lower.split())

    best_answer = None
    best_score  = 0.0

    for cat in data.get("categories", []):
        for item in cat.get("questions", []):
            candidate = re.sub(r"[^\w\s]", "", item.get("question", "").lower())
            c_words   = set(candidate.split())
            if not c_words:
                continue
            overlap = len(q_words & c_words) / max(len(q_words), len(c_words))
            if candidate and q_lower in candidate:
                overlap = max(overlap, 0.9)
            if overlap > best_score:
                best_score  = overlap
                best_answer = item.get("answer", "") or None

    return best_answer if best_score >= 0.35 else None


# ── Prompt builder ────────────────────────────────────────────────────────────
def _build_prompt(message: str) -> str:
    """Wrap the user message in Gemma-3 chat-template format."""
    return (
        f"<bos><start_of_turn>system\n{_SYSTEM_PROMPT}<end_of_turn>\n"
        f"<start_of_turn>user\n{message}<end_of_turn>\n"
        f"<start_of_turn>model\n"
    )


# ── Inference ─────────────────────────────────────────────────────────────────
def _run_inference(prompt: str) -> str:
    """Execute one forward pass. Runs in the thread-pool executor."""
    import torch

    inputs = _tokenizer(
        prompt,
        return_tensors="pt",
        truncation=True,
        max_length=1024,
    )
    inputs = {k: v.to(_device) for k, v in inputs.items()}

    with torch.no_grad():
        output_ids = _model.generate(
            **inputs,
            max_new_tokens=512,
            do_sample=True,
            temperature=0.7,
            top_p=0.9,
            repetition_penalty=1.1,
            pad_token_id=_tokenizer.eos_token_id,
        )

    # Decode only the newly generated tokens (skip the input prompt).
    new_tokens = output_ids[0][inputs["input_ids"].shape[1]:]
    return _tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


# ── Fallback ──────────────────────────────────────────────────────────────────
def _fallback(message: str) -> str:
    """
    Return a FAQ hit when available, otherwise a polite canned response.
    Used when the model is not loaded or generation fails.
    """
    hit = _faq_search(message)
    if hit:
        return hit
    return (
        "The AI model is not currently available. "
        "For barangay legal assistance please visit your barangay hall directly "
        "or contact the Lupong Tagapamayapa."
    )


# ── Public API ────────────────────────────────────────────────────────────────
def chat_response(sender: int, message: str) -> dict:
    """
    Primary entry point for POST /chats/ai.

    Accepts : { "sender": int, "message": str }
    Returns : { "response": str, "enriched": str, "sender": int }

    The model is loaded once at startup. All inference is local — no HF calls.
    """
    logger.info(f"[CHAT_REQUEST] sender={sender!r} message={message!r}")

    # Enrichment: strip leading/trailing whitespace; the fine-tuned model
    # handles domain context via the system prompt.
    enriched = message.strip()
    logger.info(f"[ENRICHED_INPUT] {enriched!r}")

    response_text = _fallback(enriched)

    if _model_loaded:
        try:
            prompt  = _build_prompt(enriched)
            future  = _executor.submit(_run_inference, prompt)
            generated = future.result(timeout=_GENERATION_TIMEOUT)
            if generated:
                response_text = generated
        except _cf.TimeoutError:
            logger.warning(
                f"[TIMEOUT] Generation exceeded {_GENERATION_TIMEOUT}s — "
                "returning FAQ fallback."
            )
        except Exception as _e:
            logger.error(f"[GENERATION_ERROR] {_e}", exc_info=True)

    logger.info(f"[MODEL_OUTPUT] sender={sender!r} response={response_text!r}")

    return {
        "response": response_text,
        "enriched": enriched,
        "sender":   sender,
    }


def generate_chat_response(
    user_input: str,
    history: List[Dict] = None,
) -> Tuple[str, Optional[str]]:
    """
    Backward-compatible wrapper kept for any existing route that imports this.
    Returns (response_text, ui_action) where ui_action is always None here.
    """
    result = chat_response(sender=0, message=user_input)
    return result["response"], None


# ── Bootstrap ─────────────────────────────────────────────────────────────────
# Load FAQ data synchronously (fast). Load the heavy ML model in a background
# thread so uvicorn starts accepting requests immediately instead of blocking
# for several minutes while the model loads into memory on CPU.
import threading as _threading
load_faq_data()
_threading.Thread(target=_load_model, daemon=True, name="bla_model_loader").start()
