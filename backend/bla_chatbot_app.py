"""
bla-chatbot-railway  —  app.py
Share this file with the colleague to replace their existing app.py.
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
# Gemma 3-IT supports the "system" role (unlike Gemma 2).
# Keep it short — 1B models struggle with long multi-rule prompts.
SYSTEM_PROMPT = (
    "You are BLA, a Philippine Barangay Legal Aid assistant. "
    "Answer clearly and helpfully. "
    "Always cite the relevant Philippine law (e.g. RA 7160, RA 9262) at the end of your answer. "
    "If the question is outside barangay jurisdiction, say so and suggest where to go. "
    "Reply in the same language the user used (Filipino or English)."
)

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

    # Gemma 3-IT uses "system" / "user" / "model" roles.
    # Convert frontend "assistant" role → "model" for Gemma.
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    for entry in history[-6:]:   # last 3 exchanges (6 entries)
        role = "model" if entry.role == "assistant" else "user"
        messages.append({"role": role, "content": entry.content})

    # Ensure last turn before the new message is "model" so Gemma alternation holds
    if messages and messages[-1]["role"] == "user":
        messages.append({"role": "model", "content": "Understood."})

    messages.append({"role": "user", "content": req.message})

    input_ids = tokenizer.apply_chat_template(
        messages,
        return_tensors="pt",
        add_generation_prompt=True,
    ).to(model.device)

    with torch.no_grad():
        output_ids = model.generate(
            input_ids,
            max_new_tokens=256,
            do_sample=True,
            temperature=0.7,
            top_p=0.9,
            repetition_penalty=1.1,
            pad_token_id=tokenizer.eos_token_id,
        )

    # Decode only the newly generated tokens (no prompt echo)
    new_tokens = output_ids[0][input_ids.shape[-1]:]
    reply = tokenizer.decode(new_tokens, skip_special_tokens=True).strip()

    # Fallback if model generates nothing
    if not reply:
        reply = (
            "I'm sorry, I couldn't generate a response. "
            "Please visit your barangay hall for legal assistance."
        )

    return {"reply": reply}
