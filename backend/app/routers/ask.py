"""
routers/ask.py – /ask endpoint for the Barangay Legal Assistant RAG chatbot.

Pipeline:
  1. Receive { "question": "..." } from the frontend
  2. Forward the question to the Railway model service
  3. Return { "question": "...", "answer": "..." } to the frontend
"""

import logging
import os
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ask", tags=["RAG Chatbot"])

# Railway model service URL
MODEL_URL = os.getenv(
    "GEMMA_URL",
    "https://bla-chatbot-railway-production.up.railway.app/chat"
)

FALLBACK_ANSWER = (
    "I don't have enough information from the provided barangay legal documents."
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
    Accepts:  { "question": "What is a barangay restraining order?" }
    Returns:  { "question": "...", "answer": "..." }
    """
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    logger.info("Forwarding question to model service: %.80s", question)

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                MODEL_URL,
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
    except httpx.RequestError as e:
        logger.error("Could not reach model service: %s", e)
        raise HTTPException(
            status_code=503,
            detail="The model service is currently unreachable. Please try again later."
        )

    # The Railway model returns {"question": ..., "answer": ...} directly.
    # Fall back gracefully if it uses a different key.
    answer = (
        raw_data.get("answer")
        or raw_data.get("reply")
        or raw_data.get("text")
        or raw_data.get("generated_text")
        or ""
    )

    if not answer:
        logger.warning("Model returned empty answer: %s", raw_data)
        answer = FALLBACK_ANSWER

    return AskResponse(question=question, answer=answer)
