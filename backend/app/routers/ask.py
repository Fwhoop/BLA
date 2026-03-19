"""
routers/ask.py – /ask endpoint for the Barangay Legal Assistant RAG chatbot.

Pipeline:
  1. Receive { "question": "..." } from the frontend
  2. Retrieve top-3 relevant chunks from the FAISS index
  3. Build a strict-JSON prompt using the BLA prompt template
  4. POST the prompt to the Gemma model service
  5. Parse the JSON response from Gemma
  6. Return { "answer": "..." } to the frontend
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


# ── Schemas ───────────────────────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    question: str
    answer: str


# ── Helpers ───────────────────────────────────────────────────────────────────

def _extract_json(raw: str) -> dict:
    """
    Attempt to parse a strict JSON object from the model's raw text output.

    Gemma is instructed to return only JSON, but may occasionally wrap it in
    markdown fences (```json ... ```) or add trailing text. This function
    handles those cases gracefully before falling back to a safe error reply.
    """
    # 1. Try direct parse first (ideal case)
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

    # 3. Extract the first {...} block found in the text
    match = re.search(r"\{.*?\}", cleaned, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            pass

    # 4. Nothing parseable – return as-is so the user still gets a response
    logger.warning("Could not parse JSON from model output: %s", raw[:200])
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

    # Step 1 – retrieve the top 3 relevant document chunks from FAISS
    try:
        chunks = retrieve_context(question, top_k=3)
    except RuntimeError as e:
        logger.error("RAG retrieval failed: %s", e)
        raise HTTPException(status_code=503, detail="RAG system not ready.")

    if not chunks:
        chunks = ["No relevant legal context found."]

    # Step 2 – build the strict-JSON prompt
    prompt = build_prompt(question, chunks)
    logger.info("Sending prompt to Gemma (%d chars) | question: %.80s", len(prompt), question)

    # Step 3 – send the prompt to the Gemma model service
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

    # Step 4 – extract the raw text from the Gemma service response
    # Gemma service may return { "answer": "..." }, { "text": "..." }, etc.
    raw_text = (
        raw_data.get("answer")
        or raw_data.get("text")
        or raw_data.get("generated_text")
        or str(raw_data)
    )

    # Step 5 – parse the JSON that Gemma was instructed to produce
    parsed = _extract_json(raw_text)

    answer = parsed.get("answer", raw_text)

    return AskResponse(question=question, answer=answer)
