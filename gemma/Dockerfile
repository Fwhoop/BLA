# Use a CUDA-enabled base if your Railway plan has a GPU; use slim otherwise.
# Switch to nvidia/cuda:12.1.0-runtime-ubuntu22.04 for GPU support.
FROM python:3.11-slim

WORKDIR /app

# Required for torch + transformers
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# PORT injected by Railway; HF_TOKEN must be set as a Railway env var
ENV PORT=9000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
