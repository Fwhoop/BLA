"""
chatbot.py — BLA FAQ search and fallback engine.

Local ML model loading has been removed. The HF Inference API is the
primary AI source (chat.py handles that). This module provides:
  - load_faq_data()        — load barangay_law_flutter.json
  - chat_response(sender, message) -> dict  — FAQ search + canned fallback
"""

import os
import re
import json
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Knowledge-base JSON bundled with the backend image.
_BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
_JSON_FILE = os.path.join(os.path.dirname(_BASE_DIR), "barangay_law_flutter.json")

logger.info(f"[STARTUP] FAQ JSON path → {_JSON_FILE}")

# ── FAQ / knowledge base ──────────────────────────────────────────────────────
_faq_cache: Optional[dict] = None


def load_faq_data() -> Optional[dict]:
    """Load barangay_law_flutter.json once and cache it."""
    global _faq_cache
    if _faq_cache is not None:
        return _faq_cache
    if not os.path.exists(_JSON_FILE):
        logger.warning(f"FAQ file not found: {_JSON_FILE}")
        return None
    try:
        with open(_JSON_FILE, "r", encoding="utf-8") as f:
            _faq_cache = json.load(f)
        logger.info(f"[STARTUP] FAQ loaded — {len(_faq_cache.get('categories', []))} categories")
    except Exception as e:
        logger.error(f"FAQ load error: {e}")
    return _faq_cache


def _faq_search(query: str) -> Optional[str]:
    """Simple keyword search over the FAQ JSON. Returns best answer or None."""
    data = load_faq_data()
    if not data:
        return None

    q_lower = re.sub(r"[^\w\s]", "", query.lower())
    q_words  = set(q_lower.split())

    best_answer = None
    best_score  = 0.0

    for cat in data.get("categories", []):
        for item in cat.get("questions", []):
            candidate = re.sub(r"[^\w\s]", "", item.get("question", "").lower())
            c_words   = set(candidate.split())
            if not c_words:
                continue
            overlap = len(q_words & c_words) / max(len(q_words), len(c_words))
            if candidate and q_lower in candidate:
                overlap = max(overlap, 0.9)
            if overlap > best_score:
                best_score  = overlap
                best_answer = item.get("answer", "") or None

    return best_answer if best_score >= 0.35 else None


# ── Public API ────────────────────────────────────────────────────────────────
def chat_response(sender: int, message: str) -> dict:
    """
    FAQ search + canned fallback. Called by chat.py when HF API is unavailable.

    Returns: { "response": str, "sender": int }
    """
    hit = _faq_search(message.strip())
    response_text = hit if hit else (
        "The AI model is not currently available. "
        "For barangay legal assistance please visit your barangay hall directly "
        "or contact the Lupong Tagapamayapa."
    )
    return {"response": response_text, "sender": sender}


# ── Bootstrap ─────────────────────────────────────────────────────────────────
load_faq_data()
