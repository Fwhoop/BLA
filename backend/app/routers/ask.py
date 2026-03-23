"""
routers/ask.py – /ask endpoint for the Barangay Legal Assistant RAG chatbot.

Pipeline:
  1. Receive { "question": "..." } from the frontend
  2. Forward { "message": "..." } to the Railway AI service
  3. Return { "question": "...", "answer": "..." } to the frontend

RAG retrieval and prompt building are handled entirely by the Railway AI service.
"""

import logging
import os
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ask", tags=["RAG Chatbot"])

# Set GEMMA_URL in Railway environment variables
GEMMA_URL = os.getenv(
    "GEMMA_URL",
    "https://bla-chatbot-railway-production.up.railway.app/chat"
)

# Shared async client — created once, reused across all requests.
# Reusing the client keeps the TCP/TLS connection alive between calls
# (HTTP keep-alive), avoiding the overhead of a new handshake every request.
_http_client = httpx.AsyncClient(
    timeout=httpx.Timeout(
        connect=5.0,   # fail fast if Railway service is unreachable
        read=30.0,     # wait up to 30 s for the model to finish generating
        write=10.0,
        pool=5.0,
    ),
    limits=httpx.Limits(
        max_keepalive_connections=5,
        max_connections=10,
        keepalive_expiry=30.0,
    ),
)


# ── Schemas ───────────────────────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    question: str
    answer: str


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/", response_model=AskResponse)
async def ask(payload: AskRequest):
    """
    Main RAG endpoint.

    Accepts:  { "question": "What is a barangay restraining order?" }
    Returns:  { "question": "...", "answer": "..." }

    Forwards the question to the Railway AI service which handles
    RAG retrieval and generation.
    """
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    logger.info("Forwarding question to model service: %.80s", question)

    try:
        response = await _http_client.post(
            GEMMA_URL,
            json={"message": question},
        )
        response.raise_for_status()
        raw_data = response.json()

    except httpx.HTTPStatusError as e:
        logger.error("Model service returned HTTP %s: %s", e.response.status_code, e.response.text)
        raise HTTPException(
            status_code=502,
            detail="The model service returned an error. Please try again."
        )
    except httpx.TimeoutException as e:
        logger.error("Model service timed out: %s", e)
        raise HTTPException(
            status_code=504,
            detail="The model took too long to respond. Please try again."
        )
    except httpx.RequestError as e:
        logger.error("Could not reach model service: %s", e)
        raise HTTPException(
            status_code=503,
            detail="The model service is currently unreachable. Please try again later."
        )

    answer = raw_data.get("reply") or raw_data.get("answer") or str(raw_data)
    return AskResponse(question=question, answer=answer)
