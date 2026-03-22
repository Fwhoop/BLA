"""
routers/ask.py – /ask endpoint for the Barangay Legal Assistant RAG chatbot.

Pipeline:
  1. Receive { "question": "..." } from the frontend
  2. Retrieve only RELEVANT chunks from FAISS (with similarity threshold)
  3. If no relevant chunks found → return fallback answer immediately (no Gemma call)
  4. Build the strict-JSON prompt using only the relevant chunks
  5. POST the prompt to the Gemma model service
  6. Parse the JSON response from Gemma
  7. Return { "question": "...", "answer": "..." } to the frontend
"""

import re
import logging
import os
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.rag import retrieve_context, build_prompt

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ask", tags=["RAG Chatbot"])

# Set GEMMA_URL in Railway environment variables
GEMMA_URL = os.getenv(
    "GEMMA_URL",
    "https://bla-chatbot-railway-production.up.railway.app/chat"
)

# Fallback answer when no relevant chunks are found in FAISS.
# Returned immediately — Gemma is never called, preventing hallucination.
NO_CONTEXT_ANSWER = (
    "I don't have enough information from the provided barangay legal documents."
)


# ── Schemas ───────────────────────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    question: str
    answer: str


# ── Helpers ───────────────────────────────────────────────────────────────────

def _strip_markdown(text: str) -> str:
    """Remove markdown formatting so plain-text frontends display cleanly."""
    # Remove bold (**text** or __text__)
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"__(.+?)__", r"\1", text)
    # Remove italic (*text* or _text_)
    text = re.sub(r"\*(.+?)\*", r"\1", text)
    text = re.sub(r"_(.+?)_", r"\1", text)
    # Remove horizontal rules
    text = re.sub(r"\n---+\n", "\n\n", text)
    return text.strip()


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/", response_model=AskResponse)
async def ask(payload: AskRequest):
    """
    Main RAG endpoint.

    Accepts:  { "question": "What is a barangay restraining order?" }
    Returns:  { "question": "...", "answer": "..." }
    """
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    # ── Step 1: Retrieve relevant chunks from FAISS ───────────────────────────
    try:
        chunks = retrieve_context(question, top_k=3)
    except RuntimeError as e:
        logger.error("RAG retrieval failed: %s", e)
        raise HTTPException(status_code=503, detail="RAG system not ready.")

    # ── Step 3: Build the strict-JSON prompt ──────────────────────────────────
    prompt = build_prompt(question, chunks)
    logger.info("Sending prompt to Gemma (%d chars, %d chunks) | question: %.80s",
                len(prompt), len(chunks), question)

    # ── Step 4: Call the Gemma model service ──────────────────────────────────
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                GEMMA_URL,
                json={"message": prompt},
            )
            response.raise_for_status()
            raw_data = response.json()

    except httpx.HTTPStatusError as e:
        logger.error("Gemma returned HTTP %s: %s", e.response.status_code, e.response.text)
        raise HTTPException(
            status_code=502,
            detail="The model service returned an error. Please try again."
        )
    except httpx.RequestError as e:
        logger.error("Could not reach Gemma service: %s", e)
        raise HTTPException(
            status_code=503,
            detail="The model service is currently unreachable. Please try again later."
        )

    # ── Step 5: Extract raw text from Gemma's response ────────────────────────
    # The Gemma service wrapper may return different key names.
    raw_text = (
        raw_data.get("reply")
        or raw_data.get("answer")
        or raw_data.get("text")
        or raw_data.get("generated_text")
        or str(raw_data)
    )

    # ── Step 6: The chatbot returns plain text (not JSON) ─────────────────────
    # Strip markdown formatting since the frontend renders plain text.
    answer = _strip_markdown(raw_text)

    return AskResponse(question=question, answer=answer)
