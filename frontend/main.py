"""
frontend/main.py – BLA Chatbot Frontend FastAPI app.

Serves the chat UI and proxies user questions to the backend /ask endpoint.

Environment variables (set in Railway):
  BACKEND_URL  – full URL of the backend service, e.g. https://bla-backend.up.railway.app
"""

import os
import logging
import httpx
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="BLA Chatbot Frontend")

# Jinja2 templates directory (frontend/templates/)
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))

# Backend service URL – override via env var on Railway
BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")
ASK_ENDPOINT = f"{BACKEND_URL}/ask/"


# ── Routes ───────────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Render the empty chat page."""
    return templates.TemplateResponse("chat.html", {"request": request, "messages": []})


@app.post("/chat", response_class=HTMLResponse)
async def chat(request: Request, question: str = Form(...)):
    """
    Receive the user's question from the HTML form,
    forward it to the backend /ask endpoint,
    and re-render the chat page with the answer.
    """
    messages = []

    # Echo the user's message first
    messages.append({"role": "user", "text": question})

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(ASK_ENDPOINT, json={"question": question})
            response.raise_for_status()
            data = response.json()
            answer = data.get("answer", "No answer returned.")
    except httpx.RequestError as e:
        logger.error("Could not reach backend: %s", e)
        answer = "Sorry, I could not reach the backend service. Please try again later."
    except httpx.HTTPStatusError as e:
        logger.error("Backend returned error %s", e.response.status_code)
        answer = f"Backend error ({e.response.status_code}). Please try again."

    messages.append({"role": "assistant", "text": answer})

    return templates.TemplateResponse("chat.html", {"request": request, "messages": messages})
