FROM python:3.11-slim

WORKDIR /app

# Install dependencies first (layer-cached)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY ./app ./app

# Copy knowledge-base JSON used by the chatbot
COPY barangay_law_flutter.json .

# Railway injects all env vars at runtime — never COPY .env into the image.
# PORT is set automatically by Railway; fall back to 8000 for local Docker use.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
