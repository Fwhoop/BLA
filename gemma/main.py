"""
gemma/main.py – Gemma LLM FastAPI service.

Accepts a prompt via POST /generate and returns the model's response.

Environment variables (set in Railway):
  MODEL_NAME  – HuggingFace model ID, e.g. "google/gemma-2b-it"
  HF_TOKEN    – HuggingFace access token (needed for gated models like Gemma)
  MAX_TOKENS  – maximum new tokens to generate (default: 512)
  PORT        – injected by Railway automatically
"""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Gemma LLM Service")

# ── Config ────────────────────────────────────────────────────────────────────
MODEL_NAME = os.getenv("MODEL_NAME", "google/gemma-2b-it")
HF_TOKEN   = os.getenv("HF_TOKEN", None)          # required for gated Gemma models
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "512"))

# ── Load model at startup ─────────────────────────────────────────────────────
_pipeline = None

@app.on_event("startup")
def load_model():
    global _pipeline
    try:
        from transformers import pipeline, AutoTokenizer, AutoModelForCausalLM
        import torch

        logger.info("Loading model: %s", MODEL_NAME)

        # Use half-precision if a GPU is available, else float32
        dtype = torch.float16 if torch.cuda.is_available() else torch.float32
        device = 0 if torch.cuda.is_available() else -1  # -1 = CPU for transformers pipeline

        tokenizer = AutoTokenizer.from_pretrained(
            MODEL_NAME,
            token=HF_TOKEN,
        )
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_NAME,
            token=HF_TOKEN,
            torch_dtype=dtype,
            device_map="auto",          # automatically place on GPU/CPU
        )

        _pipeline = pipeline(
            "text-generation",
            model=model,
            tokenizer=tokenizer,
            device=device,
            max_new_tokens=MAX_TOKENS,
            do_sample=False,            # deterministic output for legal answers
        )
        logger.info("Model loaded successfully")
    except Exception as e:
        logger.error("Failed to load model: %s", e)
        # App will still start; /generate will return 503 until model is ready


# ── Schemas ───────────────────────────────────────────────────────────────────

class GenerateRequest(BaseModel):
    prompt: str


class GenerateResponse(BaseModel):
    answer: str


# ── Endpoint ──────────────────────────────────────────────────────────────────

@app.post("/generate", response_model=GenerateResponse)
async def generate(payload: GenerateRequest):
    """
    Run the Gemma model on the provided prompt and return the generated text.
    The backend /ask router calls this endpoint with a RAG-enriched prompt.
    """
    if _pipeline is None:
        raise HTTPException(status_code=503, detail="Model is not loaded yet. Please retry.")

    prompt = payload.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="Prompt cannot be empty.")

    try:
        logger.info("Generating response for prompt (%d chars)...", len(prompt))
        outputs = _pipeline(prompt)
        # The pipeline returns a list of dicts; extract the generated text
        full_text: str = outputs[0]["generated_text"]

        # Strip the original prompt from the output (model echoes the input)
        if full_text.startswith(prompt):
            answer = full_text[len(prompt):].strip()
        else:
            answer = full_text.strip()

        logger.info("Generation complete (%d chars)", len(answer))
        return GenerateResponse(answer=answer)

    except Exception as e:
        logger.error("Generation failed: %s", e)
        raise HTTPException(status_code=500, detail=f"Generation error: {str(e)}")


@app.get("/health")
def health():
    """Simple health check used by Railway to verify the service is up."""
    return {"status": "ok", "model": MODEL_NAME, "ready": _pipeline is not None}
