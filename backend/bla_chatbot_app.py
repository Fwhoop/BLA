"""
bla-chatbot-railway  —  upgraded app.py
Share this file with the colleague to replace their existing app.py.

Changes from original:
  - hf_token read from env var (security fix)
  - SYSTEM_PROMPT forces chain-of-thought + mandatory Philippine law citations
  - ChatRequest accepts optional history list for multi-turn conversation
  - Uses tokenizer.apply_chat_template instead of raw tokenization
  - Decodes only newly generated tokens (no prompt echo)
  - max_new_tokens=300, temperature=0.6, repetition_penalty=1.15
"""

import os
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Optional
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel
import torch

app = FastAPI()

# ── Model loading ──────────────────────────────────────────────────────────────
hf_token = os.environ.get("hf_token", "")

tokenizer = AutoTokenizer.from_pretrained("google/gemma-3-1b-it", token=hf_token)
base_model = AutoModelForCausalLM.from_pretrained(
    "google/gemma-3-1b-it",
    torch_dtype=torch.float16,
    device_map="auto",
    token=hf_token,
)
model = PeftModel.from_pretrained(base_model, "./model")
model.eval()

# ── System prompt ──────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are BLA, an expert Philippine Barangay Legal Aid assistant.

RULES you must ALWAYS follow:
1. Think step-by-step before answering. Show your reasoning briefly.
2. ALWAYS cite the specific Philippine law or section (e.g., RA 7160 Section 389, RA 9262, KP Rules 2023) that applies.
3. Keep answers focused on barangay-level jurisdiction. If a matter is outside barangay authority, say so clearly and suggest where to go.
4. Respond in the same language the user used (Filipino or English).
5. Structure longer answers with numbered steps or bullet points for clarity.
6. End every answer with a short "Legal Basis:" line listing the laws cited."""


# ── Request schema ─────────────────────────────────────────────────────────────
class HistoryEntry(BaseModel):
    role: str      # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    message: str
    history: Optional[List[HistoryEntry]] = None


# ── Chat endpoint ──────────────────────────────────────────────────────────────
@app.post("/chat")
def chat(req: ChatRequest):
    history = req.history or []

    # Build turn list using Gemma roles ("user" / "model")
    # Gemma does NOT support a "system" role — embed system prompt in first user turn
    messages = []
    for i, entry in enumerate(history[-6:]):   # keep last 3 exchanges (6 entries)
        role = "model" if entry.role == "assistant" else "user"
        content = entry.content
        if i == 0 and role == "user":
            content = f"{SYSTEM_PROMPT}\n\n{content}"
        messages.append({"role": role, "content": content})

    # First message ever — wrap with system prompt
    if not messages:
        messages.append({
            "role": "user",
            "content": f"{SYSTEM_PROMPT}\n\n{req.message}",
        })
    else:
        messages.append({"role": "user", "content": req.message})

    # Gemma requires strict user→model alternation; drop consecutive same-role messages
    cleaned = [messages[0]]
    for msg in messages[1:]:
        if msg["role"] != cleaned[-1]["role"]:
            cleaned.append(msg)

    input_ids = tokenizer.apply_chat_template(
        cleaned,
        return_tensors="pt",
        add_generation_prompt=True,
    ).to(model.device)

    with torch.no_grad():
        output_ids = model.generate(
            input_ids,
            max_new_tokens=300,
            do_sample=True,
            temperature=0.6,
            top_p=0.9,
            repetition_penalty=1.15,
        )

    # Decode only the newly generated tokens (skip echoing the prompt)
    new_tokens = output_ids[0][input_ids.shape[-1]:]
    reply = tokenizer.decode(new_tokens, skip_special_tokens=True).strip()
    return {"reply": reply}
