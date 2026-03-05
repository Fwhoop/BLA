FROM python:3.11-slim

WORKDIR /app

# ── 1. Install Python dependencies (cached until requirements change) ─────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── 2. Download google/gemma-3-1b-it base model at build time ─────────────────
#    The model is baked into the image — no network access needed at runtime.
#    Set HF_TOKEN as a Railway build variable (required for gated Gemma models).
ARG HF_TOKEN
ENV HF_HOME=/app/hf_cache

RUN python -c "\
import os, torch; \
from transformers import AutoTokenizer, AutoModelForCausalLM; \
token = os.environ.get('HF_TOKEN', ''); \
model_id = 'google/gemma-3-1b-it'; \
cache = '/app/hf_cache'; \
print('Downloading tokenizer...', flush=True); \
AutoTokenizer.from_pretrained(model_id, token=token, cache_dir=cache); \
print('Downloading model weights (this may take several minutes)...', flush=True); \
AutoModelForCausalLM.from_pretrained(model_id, token=token, cache_dir=cache, torch_dtype=torch.float32); \
print('Base model downloaded successfully.', flush=True); \
"

# ── 3. Copy application code (includes app/bla_model/ LoRA adapter) ──────────
COPY ./app ./app
COPY barangay_law_flutter.json .

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
