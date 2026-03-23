"""
finetune_lora.py
────────────────
QLoRA Supervised Fine-Tuning for the BLA Barangay Legal Aid chatbot.
Target base model : google/gemma-3-1b-it
Method            : QLoRA (4-bit NF4 quantisation + LoRA adapters)
Output            : LoRA adapter  → backend/app/bla_model/lora_adapter/
                    Merged model  → backend/app/bla_model/Gemma3_BLA_full/

Requirements (install before running):
    pip install transformers>=4.49.0 peft>=0.10.0 datasets accelerate
    pip install bitsandbytes trl sentencepiece

Recommended hardware:
    • GPU with ≥ 8 GB VRAM (RTX 3060 / T4 / A10 / V100)
    • Google Colab (free T4) or Kaggle (free P100) both work

Usage:
    python finetune_lora.py
    python finetune_lora.py --no-merge     # skip full-model merge (saves time)
    python finetune_lora.py --epochs 3     # override default epoch count
"""

import argparse
import os
import sys
import time
import torch
from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    DataCollatorForSeq2Seq,
    TrainingArguments,
)
from peft import (
    LoraConfig,
    PeftModel,
    TaskType,
    get_peft_model,
    prepare_model_for_kbit_training,
)
from trl import SFTTrainer

# ─── Argument parsing ─────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="QLoRA fine-tuning for BLA Gemma 3 1B-IT")
parser.add_argument("--epochs",    type=int,  default=5,     help="Training epochs (default: 5)")
parser.add_argument("--lr",        type=float,default=2e-4,  help="Peak learning rate (default: 2e-4)")
parser.add_argument("--no-merge",  action="store_true",      help="Skip merging LoRA into full model")
parser.add_argument("--data",      type=str,  default=None,  help="Path to JSONL dataset (optional override)")
args = parser.parse_args()

# ─── Paths ────────────────────────────────────────────────────────────────────
_HERE         = os.path.dirname(os.path.abspath(__file__))
BASE_MODEL_ID = "google/gemma-3-1b-it"
DATASET_PATH  = args.data or os.path.join(_HERE, "sft_training_data.jsonl")
LORA_SAVE_DIR = os.path.join(_HERE, "backend", "app",
                              "bla_model", "lora_adapter")
FULL_SAVE_DIR = os.path.join(_HERE, "backend", "app",
                              "bla_model", "Gemma3_BLA_full")
MAX_SEQ_LEN   = 2048

# ─── System prompt — must match chatbot.py exactly ────────────────────────────
# Gemma 3 has no "system" role; the system prompt is injected into the first
# user message, which is exactly how chatbot.py formats the prompt at inference.
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

# ─── Pre-flight checks ────────────────────────────────────────────────────────
if not os.path.exists(DATASET_PATH):
    print(f"ERROR: Dataset not found at {DATASET_PATH}")
    sys.exit(1)

if not torch.cuda.is_available():
    print("WARNING: No CUDA GPU detected. Training will be extremely slow on CPU.")
    print("         Consider using Google Colab (free T4) or Kaggle (free P100).")

print(f"\n{'='*60}")
print(f"  BLA QLoRA Fine-Tuning — Gemma 3 1B-IT")
print(f"{'='*60}")
print(f"  Dataset : {DATASET_PATH}")
print(f"  LoRA out: {LORA_SAVE_DIR}")
print(f"  Full out: {FULL_SAVE_DIR}")
print(f"  Epochs  : {args.epochs}   LR: {args.lr}")
print(f"  CUDA    : {torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU only'}")
print(f"{'='*60}\n")

# ─── 4-bit Quantisation Config (QLoRA) ───────────────────────────────────────
# NF4 quantisation dramatically reduces VRAM: 1B model fits in ~2 GB
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",          # NormalFloat4 — best quality for fine-tuning
    bnb_4bit_compute_dtype=torch.bfloat16,
    bnb_4bit_use_double_quant=True,     # further 0.4 bpw saving via nested quantisation
)

# ─── Tokeniser ────────────────────────────────────────────────────────────────
print("Loading tokeniser…")
tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_ID, trust_remote_code=True)
# Gemma 3 has no dedicated pad token; reuse EOS so the collator can pad safely
tokenizer.pad_token    = tokenizer.eos_token
tokenizer.padding_side = "right"   # left-pad causes positional issues with flash-attn

# ─── Base Model ───────────────────────────────────────────────────────────────
print("Loading base model with 4-bit quantisation (this may take a minute)…")
model = AutoModelForCausalLM.from_pretrained(
    BASE_MODEL_ID,
    quantization_config=bnb_config,
    device_map="auto",
    trust_remote_code=True,
)
# Cast layer-norm and head to bfloat16 and enable gradient checkpointing
model = prepare_model_for_kbit_training(model)

# ─── LoRA Configuration ───────────────────────────────────────────────────────
# Target all major projection layers in Gemma 3's decoder blocks:
#   q_proj / k_proj / v_proj / o_proj  — multi-head attention
#   gate_proj / up_proj / down_proj     — SwiGLU feed-forward network
# Higher rank (r=16) → more capacity to learn legal domain nuances.
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,          # effective scale = alpha / r = 2
    target_modules=[
        "q_proj", "k_proj", "v_proj", "o_proj",
        "gate_proj", "up_proj", "down_proj",
    ],
    lora_dropout=0.05,
    bias="none",
    task_type=TaskType.CAUSAL_LM,
)

model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
# Expected: ~4–8 M trainable params out of ~1 B (≈ 0.4–0.8%)

# ─── Dataset Preprocessing ────────────────────────────────────────────────────
print("\nLoading and tokenising dataset…")
raw_dataset = load_dataset("json", data_files=DATASET_PATH)["train"]


def preprocess(sample: dict) -> dict:
    """
    Convert one SFT record into tokenised input_ids + labels.

    Prompt format (matches chatbot.py inference exactly):
        <bos><start_of_turn>user
        {SYSTEM_PROMPT}

        {instruction}

        {input}<end_of_turn>
        <start_of_turn>model
        {output}<end_of_turn>

    Labels are -100 for every prompt token (no loss on the question/instruction),
    and real token IDs for the model-response tokens (loss computed here only).
    """
    user_content = f"{SYSTEM_PROMPT}\n\n{sample['instruction']}\n\n{sample['input']}"

    # ── Prompt only (to find the boundary for label masking) ──────────────────
    prompt_text = tokenizer.apply_chat_template(
        [{"role": "user", "content": user_content}],
        tokenize=False,
        add_generation_prompt=True,   # appends <start_of_turn>model\n
    )

    # ── Full conversation including model response ─────────────────────────────
    full_text = tokenizer.apply_chat_template(
        [
            {"role": "user",      "content": user_content},
            {"role": "assistant", "content": sample["output"]},
        ],
        tokenize=False,
        add_generation_prompt=False,
    )

    # Tokenise full text; derive prompt length separately (no full decode needed)
    full_enc = tokenizer(
        full_text,
        truncation=True,
        max_length=MAX_SEQ_LEN,
        add_special_tokens=False,
    )

    input_ids      = full_enc["input_ids"]
    attention_mask = full_enc["attention_mask"]
    prompt_len     = len(tokenizer.encode(prompt_text, add_special_tokens=False))

    # Mask the prompt/instruction tokens; only compute loss on the response
    labels = [-100] * prompt_len + input_ids[prompt_len:]

    return {
        "input_ids":      input_ids,
        "attention_mask": attention_mask,
        "labels":         labels,
    }


tokenized_dataset = raw_dataset.map(
    preprocess,
    remove_columns=raw_dataset.column_names,
    desc="Tokenising",
)

tok_lengths = [len(x) for x in tokenized_dataset["input_ids"]]
print(f"  Samples       : {len(tokenized_dataset)}")
print(f"  Token lengths : avg={sum(tok_lengths)/len(tok_lengths):.0f}  "
      f"min={min(tok_lengths)}  max={max(tok_lengths)}")

# ─── Data Collator ────────────────────────────────────────────────────────────
# DataCollatorForSeq2Seq pads input_ids, attention_mask, and labels to the
# longest sequence in each batch, padding labels with -100 (not counted in loss).
data_collator = DataCollatorForSeq2Seq(
    tokenizer=tokenizer,
    model=model,
    padding=True,
    pad_to_multiple_of=8,     # memory alignment for tensor cores
    label_pad_token_id=-100,
)

# ─── Training Arguments ───────────────────────────────────────────────────────
os.makedirs(LORA_SAVE_DIR, exist_ok=True)

training_args = TrainingArguments(
    output_dir=LORA_SAVE_DIR,

    # ── Epochs / batch ──────────────────────────────────────────────────────
    num_train_epochs=args.epochs,
    per_device_train_batch_size=1,
    gradient_accumulation_steps=4,   # effective batch = 4 samples

    # ── Gradient / memory optimisations ─────────────────────────────────────
    gradient_checkpointing=True,     # trades compute for VRAM
    max_grad_norm=0.3,               # clip gradients — stabilises QLoRA training
    optim="paged_adamw_32bit",       # memory-efficient paged Adam for QLoRA

    # ── Learning rate schedule ───────────────────────────────────────────────
    learning_rate=args.lr,
    lr_scheduler_type="cosine",
    warmup_ratio=0.05,
    weight_decay=0.01,

    # ── Precision ────────────────────────────────────────────────────────────
    bf16=True,     # bfloat16 mixed precision (use fp16=True on older GPUs)
    fp16=False,

    # ── Logging / saving ─────────────────────────────────────────────────────
    logging_steps=5,
    save_strategy="epoch",
    report_to="none",               # set "wandb" or "tensorboard" for tracking

    # ── Misc ─────────────────────────────────────────────────────────────────
    dataloader_num_workers=0,       # avoid multiprocessing issues on Windows
    remove_unused_columns=False,    # our collator needs all columns
)

# ─── Trainer ──────────────────────────────────────────────────────────────────
trainer = SFTTrainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_dataset,
    data_collator=data_collator,
    tokenizer=tokenizer,
)

# ─── Train ────────────────────────────────────────────────────────────────────
print(f"\nStarting training ({args.epochs} epoch(s))…")
t0 = time.time()
trainer.train()
elapsed = time.time() - t0
print(f"\nTraining complete in {elapsed/60:.1f} min.")

# ─── Save LoRA adapter ────────────────────────────────────────────────────────
print(f"\nSaving LoRA adapter → {LORA_SAVE_DIR}")
model.save_pretrained(LORA_SAVE_DIR)
tokenizer.save_pretrained(LORA_SAVE_DIR)
print("  adapter_config.json + adapter_model.safetensors written.")

# ─── Merge and Save Full Model ────────────────────────────────────────────────
# chatbot.py prefers the full merged model (Strategy 1) for faster inference
# because it avoids dynamic PEFT layer insertion at load time.
if not args.no_merge:
    print(f"\nMerging LoRA weights into base model (runs on CPU to avoid VRAM spike)…")
    os.makedirs(FULL_SAVE_DIR, exist_ok=True)

    # Reload base in bfloat16 on CPU — quantised model cannot be directly merged
    base_cpu = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL_ID,
        torch_dtype=torch.bfloat16,
        device_map="cpu",
        trust_remote_code=True,
    )
    merged = PeftModel.from_pretrained(base_cpu, LORA_SAVE_DIR)
    merged = merged.merge_and_unload()          # fuse LoRA A×B into W and discard adapters

    print(f"Saving merged model → {FULL_SAVE_DIR}")
    merged.save_pretrained(FULL_SAVE_DIR)
    tokenizer.save_pretrained(FULL_SAVE_DIR)
    print("  config.json + model.safetensors (or shards) written.")
    del merged, base_cpu

print("\n" + "="*60)
print("  Fine-tuning complete!")
print(f"  LoRA adapter : {LORA_SAVE_DIR}")
if not args.no_merge:
    print(f"  Full model   : {FULL_SAVE_DIR}")
print("="*60)
print("\nNext step: run  python test_lora_adapter.py  to verify the model.\n")
