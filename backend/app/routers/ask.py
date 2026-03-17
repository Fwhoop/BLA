"""
routers/ask.py – /ask endpoint for the RAG chatbot.

Flow:
  1. Receive user question via POST /ask
  2. Retrieve top-3 relevant chunks from FAISS (via rag.py)
  3. Build a prompt combining context + question
  4. Forward the prompt to the Gemma LLM service (Railway-hosted)
  5. Return Gemma's answer as JSON
"""

import os
import logging
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.rag import retrieve_context, build_prompt

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ask", tags=["RAG Chatbot"])

# URL of the Gemma FastAPI service – set via env var GEMMA_URL on Railway
GEMMA_URL = os.getenv("GEMMA_URL", "http://localhost:9000/generate")


# ── Request / Response schemas ───────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    question: str
    answer: str
    context_used: list[str]   # the chunks that informed the answer (for debugging)


# ── Endpoint ─────────────────────────────────────────────────────────────────

@router.post("/", response_model=AskResponse)
async def ask(payload: AskRequest):
    """
    Main RAG endpoint.
    Accepts { "question": "..." } and returns the LLM's answer.
    """
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    # Step 1 – retrieve relevant context chunks
    try:
        chunks = retrieve_context(question, top_k=3)
    except RuntimeError as e:
        logger.error("RAG retrieval failed: %s", e)
        raise HTTPException(status_code=503, detail="RAG system not ready.")

    if not chunks:
        chunks = ["No relevant legal context found."]

    # Step 2 – build the prompt
    prompt = build_prompt(question, chunks)
    logger.info("Sending prompt to Gemma (%d chars)", len(prompt))

    # Step 3 – call the Gemma LLM service
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                GEMMA_URL,
                json={"prompt": prompt},
            )
            response.raise_for_status()
            gemma_data = response.json()
    except httpx.HTTPStatusError as e:
        logger.error("Gemma returned HTTP %s: %s", e.response.status_code, e.response.text)
        raise HTTPException(status_code=502, detail=f"Gemma service error: {e.response.status_code}")
    except httpx.RequestError as e:
        logger.error("Could not reach Gemma service: %s", e)
        raise HTTPException(status_code=503, detail="Gemma LLM service is unreachable.")

    # Step 4 – extract answer (Gemma service returns { "answer": "..." })
    answer = gemma_data.get("answer") or gemma_data.get("text") or str(gemma_data)

    return AskResponse(question=question, answer=answer, context_used=chunks)
