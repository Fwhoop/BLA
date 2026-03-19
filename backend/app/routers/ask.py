"""
routers/ask.py – /ask endpoint for the Barangay Legal Assistant RAG chatbot.

Pipeline:
  1. Receive { "question": "..." } from the frontend
  2. Retrieve top-3 relevant chunks from the FAISS index
  3. Build the prompt using the BLA prompt template
  4. POST the prompt to the Gemma model service
  5. Return { "answer": "..." } to the frontend
"""

import os
import logging
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.rag import retrieve_context, build_prompt

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ask", tags=["RAG Chatbot"])

# URL of the Gemma model service – set GEMMA_URL in Railway environment variables
GEMMA_URL = os.getenv("GEMMA_URL", "https://bla-chatbot-railway-production.up.railway.app/chat")


# ── Schemas ───────────────────────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    answer: str


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/", response_model=AskResponse)
async def ask(payload: AskRequest):
    """
    Main RAG endpoint.

    Accepts  { "question": "What is a barangay restraining order?" }
    Returns  { "answer":   "..." }
    """
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    # Step 1 – retrieve the top 3 relevant document chunks from FAISS
    try:
        chunks = retrieve_context(question, top_k=3)
    except RuntimeError as e:
        logger.error("RAG retrieval failed: %s", e)
        raise HTTPException(status_code=503, detail="RAG system not ready.")

    if not chunks:
        chunks = ["No relevant legal context found."]

    # Step 2 – build the prompt with retrieved context
    prompt = build_prompt(question, chunks)
    logger.info("Built prompt (%d chars) for question: %s", len(prompt), question[:80])

    # Step 3 – send the prompt to the Gemma model service
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                GEMMA_URL,
                json={"prompt": prompt},
            )
            response.raise_for_status()
            data = response.json()

    except httpx.HTTPStatusError as e:
        logger.error("Gemma service returned HTTP %s: %s",
                     e.response.status_code, e.response.text)
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

    # Step 4 – extract the answer from the model response
    # Gemma service is expected to return { "answer": "..." }
    answer = (
        data.get("answer")
        or data.get("text")
        or data.get("generated_text")
        or str(data)
    )

    return AskResponse(answer=answer)
