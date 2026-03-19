"""
rag.py – RAG helpers for the Barangay Legal Assistant backend.

Loads the FAISS index and chunked documents once at startup, then exposes:
  - load_rag_resources()         → called by FastAPI startup event
  - retrieve_context()           → returns top-k relevant chunks + their distances
  - build_prompt()               → builds the strict JSON prompt for the Gemma model
  - RELEVANCE_THRESHOLD          → tune this to tighten/loosen what counts as "relevant"
"""

import os
import pickle
import logging
import numpy as np
import faiss
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)

# ── File paths ────────────────────────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(os.path.dirname(BASE_DIR), "data")   # backend/data/
FAISS_PATH = os.path.join(DATA_DIR, "bla_rag_index.faiss")
DOCS_PATH  = os.path.join(DATA_DIR, "bla_chunked_docs.pkl")

# ── Relevance threshold ───────────────────────────────────────────────────────
# For L2 indexes:  LOWER distance = MORE similar (0.0 = identical).
#                  Chunks with distance > threshold are discarded as irrelevant.
# For IP indexes:  HIGHER score = MORE similar.
#                  Chunks with score < threshold are discarded.
# Tune this value if too many / too few chunks are being used.
L2_THRESHOLD = float(os.getenv("RAG_L2_THRESHOLD", "1.5"))
IP_THRESHOLD = float(os.getenv("RAG_IP_THRESHOLD", "0.3"))

# ── Module-level singletons ───────────────────────────────────────────────────
_index:  faiss.Index         | None = None
_chunks: list[str]           | None = None
_model:  SentenceTransformer | None = None


def load_rag_resources() -> None:
    """
    Called once on FastAPI startup.
    Loads the SentenceTransformer model, the FAISS index, and the
    chunked documents into module-level singletons.
    """
    global _index, _chunks, _model

    # 1. Load embedding model (must match the model used when building the index)
    model_path = os.path.join(BASE_DIR, "bla_chatbot_model")
    if os.path.isdir(model_path):
        logger.info("Loading local embedding model from %s", model_path)
        _model = SentenceTransformer(model_path)
    else:
        logger.info("Local model not found – downloading paraphrase-multilingual-MiniLM-L12-v2")
        _model = SentenceTransformer("paraphrase-multilingual-MiniLM-L12-v2")

    # 2. Load FAISS index
    if not os.path.exists(FAISS_PATH):
        raise FileNotFoundError(f"FAISS index not found: {FAISS_PATH}")
    _index = faiss.read_index(FAISS_PATH)
    logger.info("FAISS index loaded – %d vectors | metric: %s",
                _index.ntotal,
                "L2" if _index.metric_type == faiss.METRIC_L2 else "IP")

    # 3. Load chunked documents
    if not os.path.exists(DOCS_PATH):
        raise FileNotFoundError(f"Chunked docs not found: {DOCS_PATH}")
    with open(DOCS_PATH, "rb") as f:
        _chunks = pickle.load(f)
    logger.info("Chunked docs loaded – %d chunks", len(_chunks))


def retrieve_context(question: str, top_k: int = 3) -> list[str]:
    """
    Embed *question*, search the FAISS index for the *top_k* nearest chunks,
    then discard any chunk whose similarity score is below the relevance
    threshold.

    Returns only the chunks that are genuinely relevant.
    Returns an empty list if nothing in the index is close enough —
    the caller must handle this case and NOT pass empty context to Gemma.
    """
    if _model is None or _index is None or _chunks is None:
        raise RuntimeError("RAG resources not loaded. Call load_rag_resources() first.")

    # Encode the question into a float32 vector
    query_vector = _model.encode([question], convert_to_numpy=True).astype("float32")

    # Search FAISS for nearest neighbours
    distances, indices = _index.search(query_vector, top_k)

    is_l2 = (_index.metric_type == faiss.METRIC_L2)
    results = []

    for dist, idx in zip(distances[0], indices[0]):
        if idx < 0 or idx >= len(_chunks):
            continue  # FAISS can return -1 when the index has fewer items than top_k

        # Apply threshold filter
        if is_l2:
            relevant = dist <= L2_THRESHOLD      # lower distance = more similar
        else:
            relevant = dist >= IP_THRESHOLD      # higher score = more similar

        if relevant:
            results.append(_chunks[idx])
        else:
            logger.debug("Chunk %d discarded (distance=%.4f, threshold=%s)",
                         idx, dist, L2_THRESHOLD if is_l2 else IP_THRESHOLD)

    logger.info("Retrieved %d/%d relevant chunks for question: %.80s",
                len(results), top_k, question)
    return results


def build_prompt(question: str, context_chunks: list[str]) -> str:
    """
    Build a prompt that forces Gemma to:
    - Respond ONLY with strict JSON.
    - Never invent RA numbers, KP rules, or any law outside the [CONTEXT].
    - Use general knowledge ONLY for non-legal practical questions.

    NOTE: Only call this when context_chunks is non-empty.
    If no relevant chunks were found, return the fallback answer directly
    in ask.py without calling Gemma at all.
    """
    context_block = "\n\n".join(context_chunks)

    prompt = (
        "You are a Barangay Legal Assistant that helps Filipino citizens understand "
        "barangay laws, dispute procedures, and community concerns in the Philippines.\n\n"

        # ── Output format ─────────────────────────────────────────────────────
        "OUTPUT RULE: Respond with ONLY a single JSON object. "
        "No text, no markdown, no explanation before or after the JSON.\n\n"
        "Required format:\n"
        '{"question": "<copy the user question exactly>", "answer": "<your answer>"}\n\n'

        # ── Anti-hallucination rules ──────────────────────────────────────────
        "STRICT RULES FOR LEGAL QUESTIONS:\n"
        "* Use ONLY the information inside the [CONTEXT] block below.\n"
        "* NEVER invent, guess, or assume any Republic Act (RA) number, "
        "Katarungang Pambarangay (KP) rule, barangay ordinance, or legal provision "
        "that does not appear word-for-word in the [CONTEXT].\n"
        "* If the specific law, RA number, or procedure is NOT in the [CONTEXT], "
        "the answer field must be exactly:\n"
        "  \"I don't have enough information from the provided barangay legal documents.\"\n"
        "* Do NOT paraphrase or recall laws from your training data. "
        "Only use what is explicitly written in the [CONTEXT].\n\n"

        # ── Exception for practical questions ─────────────────────────────────
        "RULE FOR PRACTICAL / HEALTH / SAFETY QUESTIONS:\n"
        "* For non-legal questions (e.g. animal bites, first aid, emergencies, "
        "general community concerns) you may use general knowledge.\n"
        "* Still return strict JSON. "
        "You may suggest contacting the barangay health center or local authority "
        "when relevant.\n\n"

        # ── Retrieved context ─────────────────────────────────────────────────
        f"[CONTEXT]\n{context_block}\n[END CONTEXT]\n\n"

        f"Question:\n{question}\n\n"

        # ── Final reminder (placed right before the response to reduce drift) ─
        "REMEMBER: Return ONLY the JSON object. "
        "Do not add any RA numbers or laws that are not in [CONTEXT].\n\n"
        "JSON Response:"
    )
    return prompt
