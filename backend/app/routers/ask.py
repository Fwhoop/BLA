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

import json
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

def _extract_json(raw: str) -> dict:
    """
    Parse a JSON object from Gemma's raw text output.

    Gemma is instructed to return only JSON, but may occasionally:
    - Wrap the output in markdown fences (```json ... ```)
    - Add a short sentence before or after the JSON

    This function handles those cases before falling back to returning
    the raw text as the answer so the user is never left with nothing.
    """
    # 1. Direct parse (ideal case — Gemma returned clean JSON)
    try:
        return json.loads(raw.strip())
    except json.JSONDecodeError:
        pass

    # 2. Strip markdown fences and retry
    cleaned = re.sub(r"```(?:json)?|```", "", raw).strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    # 3. Extract the first complete {...} block found anywhere in the text
    match = re.search(r"\{.*\}", cleaned, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            pass

    # 4. Nothing parseable — return the raw text so the user gets something
    logger.warning("Could not parse JSON from model output: %s", raw[:300])
    return {"answer": raw.strip()}


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

    # ── Step 2: Short-circuit if no relevant chunks found ────────────────────
    # This is the main hallucination guard.
    # If FAISS found nothing relevant, we return the fallback answer directly
    # without calling Gemma at all — so it has no opportunity to invent laws.
    if not chunks:
        logger.info("No relevant chunks found for question: %.80s", question)
        return AskResponse(question=question, answer=NO_CONTEXT_ANSWER)

    # ── Step 3: Build the strict-JSON prompt ──────────────────────────────────
    prompt = build_prompt(question, chunks)
    logger.info("Sending prompt to Gemma (%d chars, %d chunks) | question: %.80s",
                len(prompt), len(chunks), question)

    # ── Step 4: Call the Gemma model service ──────────────────────────────────
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                GEMMA_URL,
                json={"prompt": prompt},
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
        raw_data.get("answer")
        or raw_data.get("text")
        or raw_data.get("generated_text")
        or str(raw_data)
    )

    # ── Step 6: Parse the JSON Gemma was instructed to produce ────────────────
    parsed = _extract_json(raw_text)
    answer = parsed.get("answer", raw_text)

    # ── Step 7: Sanity check — catch hallucinated citations ──────────────────
    # If the answer contains legal citation patterns (RA numbers, KP articles,
    # Legal Basis sections) that do NOT appear in the retrieved chunks,
    # replace with the fallback answer.
    CITATION_PATTERNS = [
        "legal basis", "republic act", " ra ", "r.a.", "kp article",
        "article ", "section ", "under ra", "p.d.", "presidential decree",
    ]
    context_combined = " ".join(chunks).lower()
    answer_lower = answer.lower()

    for pattern in CITATION_PATTERNS:
        if pattern in answer_lower and pattern not in context_combined:
            logger.warning(
                "Hallucination detected — Gemma used '%s' not found in context. "
                "Replacing with fallback. Question: %s", pattern, question
            )
            answer = NO_CONTEXT_ANSWER
            break

    return AskResponse(question=question, answer=answer)
