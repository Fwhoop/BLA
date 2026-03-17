"""
rag.py – Retrieval-Augmented Generation helpers for the BLA backend.

Loads the FAISS index and chunked documents once at startup, then exposes
`retrieve_context()` so the /ask router can get the most relevant chunks
for any user question.
"""

import os
import pickle
import logging
import numpy as np
import faiss
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(os.path.dirname(BASE_DIR), "data")   # backend/data/
FAISS_PATH = os.path.join(DATA_DIR, "bla_rag_index.faiss")
DOCS_PATH  = os.path.join(DATA_DIR, "bla_chunked_docs.pkl")

# ── Module-level singletons (populated by load_rag_resources) ─────────────
_index:  faiss.Index | None       = None
_chunks: list[str]  | None       = None
_model:  SentenceTransformer | None = None


def load_rag_resources() -> None:
    """
    Called once on FastAPI startup.
    Loads the SentenceTransformer embedding model, the FAISS index, and the
    list of chunked document strings into module-level singletons.
    """
    global _index, _chunks, _model

    # 1. Load embedding model (same model used when building the index)
    model_path = os.path.join(BASE_DIR, "bla_chatbot_model")
    if os.path.isdir(model_path):
        logger.info("Loading local embedding model from %s", model_path)
        _model = SentenceTransformer(model_path)
    else:
        logger.info("Local model not found – downloading paraphrase-multilingual-MiniLM-L12-v2")
        _model = SentenceTransformer("paraphrase-multilingual-MiniLM-L12-v2")

    # 2. Load FAISS index
    if not os.path.exists(FAISS_PATH):
        logger.error("FAISS index not found at %s", FAISS_PATH)
        raise FileNotFoundError(f"FAISS index missing: {FAISS_PATH}")
    _index = faiss.read_index(FAISS_PATH)
    logger.info("FAISS index loaded – %d vectors", _index.ntotal)

    # 3. Load chunked documents
    if not os.path.exists(DOCS_PATH):
        logger.error("Chunked docs not found at %s", DOCS_PATH)
        raise FileNotFoundError(f"Chunked docs missing: {DOCS_PATH}")
    with open(DOCS_PATH, "rb") as f:
        _chunks = pickle.load(f)
    logger.info("Chunked docs loaded – %d chunks", len(_chunks))


def retrieve_context(question: str, top_k: int = 3) -> list[str]:
    """
    Encode *question* with the embedding model, search FAISS for the
    *top_k* nearest chunks, and return them as a list of strings.
    """
    if _model is None or _index is None or _chunks is None:
        raise RuntimeError("RAG resources are not loaded yet. Call load_rag_resources() first.")

    # Encode the user question into a float32 vector
    query_vector = _model.encode([question], convert_to_numpy=True).astype("float32")

    # Search the FAISS index
    distances, indices = _index.search(query_vector, top_k)

    # Collect the matching chunks (guard against out-of-range indices)
    results = []
    for idx in indices[0]:
        if 0 <= idx < len(_chunks):
            results.append(_chunks[idx])

    return results


def build_prompt(question: str, context_chunks: list[str]) -> str:
    """
    Combine retrieved context chunks with the user question into a
    prompt string ready to be sent to the Gemma LLM endpoint.
    """
    context_block = "\n\n---\n\n".join(context_chunks)
    prompt = (
        "You are a helpful Barangay Legal Assistant. "
        "Use only the context below to answer the question. "
        "If the answer is not in the context, say you don't have enough information.\n\n"
        f"CONTEXT:\n{context_block}\n\n"
        f"QUESTION: {question}\n\n"
        "ANSWER:"
    )
    return prompt
