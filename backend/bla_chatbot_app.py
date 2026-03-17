"""
bla-chatbot-railway  —  app.py
Share this file with the colleague to replace their existing app.py.
"""

import os
import logging
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel
import torch

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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

SYSTEM_PROMPT = (
    "You are BLA, a Philippine Barangay Legal Aid assistant. "
    "Answer clearly and helpfully. "
    "Always cite the relevant Philippine law (e.g. RA 7160, RA 9262) at the end of your answer. "
    "If the question is outside barangay jurisdiction, say so and suggest where to go. "
    "Reply in the same language the user used (Filipino or English)."
)

FALLBACK_REPLY = (
    "I'm sorry, I couldn't process your request right now. "
    "Please visit your barangay hall for legal assistance."
)

# ── Request schema ─────────────────────────────────────────────────────────────
class HistoryEntry(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    history: Optional[List[HistoryEntry]] = None


# ── Helpers ────────────────────────────────────────────────────────────────────
def _build_input_ids(req: ChatRequest):
    """Try apply_chat_template with system role, fall back to user-embedded prompt."""
    history = req.history or []
    history_turns = []
    for entry in history[-6:]:
        role = "model" if entry.role == "assistant" else "user"
        history_turns.append({"role": role, "content": entry.content})

    # Strategy 1: system role (Gemma 3-IT supports it)
    try:
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]
        messages += history_turns
        messages.append({"role": "user", "content": req.message})
        input_ids = tokenizer.apply_chat_template(
            messages,
            return_tensors="pt",
            add_generation_prompt=True,
        ).to(model.device)
        logger.info("Using chat template with system role")
        return input_ids
    except Exception as e:
        logger.warning(f"System role failed ({e}), trying user-embedded prompt")

    # Strategy 2: embed system prompt in first user message
    try:
        if history_turns:
            history_turns[0]["content"] = f"{SYSTEM_PROMPT}\n\n{history_turns[0]['content']}"
            messages = history_turns + [{"role": "user", "content": req.message}]
        else:
            messages = [{"role": "user", "content": f"{SYSTEM_PROMPT}\n\n{req.message}"}]
        input_ids = tokenizer.apply_chat_template(
            messages,
            return_tensors="pt",
            add_generation_prompt=True,
        ).to(model.device)
        logger.info("Using chat template with embedded system prompt")
        return input_ids
    except Exception as e:
        logger.warning(f"Chat template failed ({e}), using raw tokenization")

    # Strategy 3: raw tokenization (original approach)
    prompt = f"{SYSTEM_PROMPT}\n\nUser: {req.message}\nAssistant:"
    input_ids = tokenizer(prompt, return_tensors="pt").input_ids.to(model.device)
    logger.info("Using raw tokenization fallback")
    return input_ids


# ── Chat endpoint ──────────────────────────────────────────────────────────────
@app.post("/chat")
def chat(req: ChatRequest):
    try:
        input_ids = _build_input_ids(req)

        with torch.no_grad():
            output_ids = model.generate(
                input_ids,
                max_new_tokens=100,
                do_sample=False,
                repetition_penalty=1.1,
                pad_token_id=tokenizer.eos_token_id if tokenizer.eos_token_id else 1,
            )

        new_tokens = output_ids[0][input_ids.shape[-1]:]
        reply = tokenizer.decode(new_tokens, skip_special_tokens=True).strip()

        if not reply:
            logger.warning("Model generated empty reply")
            reply = FALLBACK_REPLY

        logger.info(f"Reply ({len(reply)} chars): {reply[:80]}...")
        return {"reply": reply}

    except torch.cuda.OutOfMemoryError:
        logger.error("CUDA OOM during generation")
        torch.cuda.empty_cache()
        return JSONResponse(status_code=503, content={"detail": "Model busy, try again."})
    except Exception as e:
        logger.error(f"Generation error: {e}", exc_info=True)
        return {"reply": FALLBACK_REPLY}
