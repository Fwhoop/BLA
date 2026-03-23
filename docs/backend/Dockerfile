FROM python:3.11-slim

WORKDIR /app

# Install system libs needed by faiss-cpu and sentence-transformers
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# ── Install Python dependencies ───────────────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Copy application code ─────────────────────────────────────────────────────
COPY ./app ./app
COPY barangay_law_flutter.json .
COPY run.py .

# Copy FAISS index and chunked docs
COPY ./data ./data

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
