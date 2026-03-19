"""
rag.py – RAG helpers for the Barangay Legal Assistant backend.

Loads the FAISS index and chunked documents once at startup, then exposes:
  - load_rag_resources()  → called by FastAPI startup event
  - retrieve_context()    → returns top-k relevant chunks for a question
  - build_prompt()        → builds the final prompt string for the Gemma model
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

# ── Module-level singletons ───────────────────────────────────────────────────
_index:  faiss.Index        | None = None
_chunks: list[str]          | None = None
_model:  SentenceTransformer| None = None


def load_rag_resources() -> None:
    """
    Called once on FastAPI startup.
    Loads the SentenceTransformer model, the FAISS index, and the
    chunked documents into module-level singletons.
    """
    global _index, _chunks, _model

    # 1. Load embedding model (same model used when building the FAISS index)
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
    logger.info("FAISS index loaded – %d vectors", _index.ntotal)

    # 3. Load chunked documents
    if not os.path.exists(DOCS_PATH):
        raise FileNotFoundError(f"Chunked docs not found: {DOCS_PATH}")
    with open(DOCS_PATH, "rb") as f:
        _chunks = pickle.load(f)
    logger.info("Chunked docs loaded – %d chunks", len(_chunks))


def retrieve_context(question: str, top_k: int = 3) -> list[str]:
    """
    Embed *question* and search the FAISS index for the *top_k*
    nearest document chunks. Returns a list of chunk strings.
    """
    if _model is None or _index is None or _chunks is None:
        raise RuntimeError("RAG resources not loaded. Call load_rag_resources() first.")

    # Encode the question into a float32 vector
    query_vector = _model.encode([question], convert_to_numpy=True).astype("float32")

    # Search FAISS for nearest neighbours
    _distances, indices = _index.search(query_vector, top_k)

    # Collect matching chunks (guard against out-of-range indices from FAISS)
    results = [_chunks[i] for i in indices[0] if 0 <= i < len(_chunks)]
    return results


def build_prompt(question: str, context_chunks: list[str]) -> str:
    """
    Combine retrieved context chunks with the user question into the
    prompt string that will be sent to the Gemma model service.
    """
    context_block = "\n\n".join(context_chunks)

    prompt = (
        "You are a Barangay Legal Assistant that helps citizens understand "
        "barangay laws, dispute procedures, and community concerns in the Philippines.\n\n"
        "Rules:\n"
        "* For questions about barangay laws, legal procedures, or dispute resolution: "
        "use ONLY the information in the context below. Do not invent legal information. "
        "If the answer is not in the context, say: "
        "\"I don't have enough information from the provided barangay legal documents.\"\n"
        "* For practical, health, or safety questions (such as animal bites, first aid, "
        "emergencies, or general community concerns): answer helpfully using your general "
        "knowledge. You may also suggest contacting the barangay health center or relevant "
        "local authority when appropriate.\n\n"
        f"Context:\n{context_block}\n\n"
        f"Question:\n{question}\n\n"
        "Answer:"
    )
    return prompt
