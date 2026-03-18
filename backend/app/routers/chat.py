from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from .. import models, schemas
from ..db import get_db
from ..chatbot import (
    load_faq_data,
    chat_response as _faq_fallback,
    get_local_answer as _local_answer,
    get_instant_answer as _instant_answer,
    get_legal_context as _get_legal_context,
)

import os
import logging
import requests
from requests import RequestException

logger = logging.getLogger(__name__)

_HF_API_TOKEN        = os.environ.get("HF_API_TOKEN", "")
_HF_MODEL_ID         = os.environ.get("HF_MODEL_ID", "fwhoop/bla_model")
_HF_ENDPOINT         = f"https://api-inference.huggingface.co/models/{_HF_MODEL_ID}"
_CHATBOT_SERVICE_URL = os.environ.get("CHATBOT_SERVICE_URL", "")

router = APIRouter(prefix="/chats", tags=["chats"])


@router.post("/", response_model=schemas.ChatRead)
def create_chat(chat: schemas.ChatCreate, db: Session = Depends(get_db)):
    sender   = db.query(models.User).filter(models.User.id == chat.sender_id).first()
    receiver = db.query(models.User).filter(models.User.id == chat.receiver_id).first()
    if not sender or not receiver:
        raise HTTPException(status_code=404, detail="Sender or receiver not found")

    new_chat = models.Chat(
        sender_id=chat.sender_id,
        receiver_id=chat.receiver_id,
        message=chat.message,
        created_at=datetime.utcnow(),
    )
    db.add(new_chat)
    db.commit()
    db.refresh(new_chat)
    return new_chat


@router.get("/", response_model=List[schemas.ChatRead])
def get_all_chats(db: Session = Depends(get_db)):
    return db.query(models.Chat).all()


@router.get("/faq")
def get_faq_data():
    try:
        faq_data = load_faq_data()
        if faq_data is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="FAQ data not available")
        return faq_data
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error loading FAQ data: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to load FAQ data: {str(e)}")


@router.get("/{chat_id}", response_model=schemas.ChatRead)
def get_chat(chat_id: int, db: Session = Depends(get_db)):
    chat = db.query(models.Chat).filter(models.Chat.id == chat_id).first()
    if not chat:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found")
    return chat


def _call_hf_model(message: str) -> Optional[str]:
    """Call HuggingFace Inference API. Returns text or None on failure."""
    if not _HF_API_TOKEN:
        return None

    # Build the same system-prompt format the model was fine-tuned on.
    system_prompt = (
        "You are a Philippine Barangay Legal Advisory AI Assistant (BLA). "
        "Provide structured legal guidance limited to barangay-level jurisdiction "
        "under Philippine law (RA 7160, RA 9262, etc.). "
        "If outside barangay jurisdiction, say so. "
        "Always cite the relevant Philippine law."
    )
    prompt = (
        f"<bos><start_of_turn>system\n{system_prompt}<end_of_turn>\n"
        f"<start_of_turn>user\n{message}<end_of_turn>\n"
        f"<start_of_turn>model\n"
    )

    headers = {"Authorization": f"Bearer {_HF_API_TOKEN}"}
    payload = {
        "inputs": prompt,
        "parameters": {
            "max_new_tokens": 512,
            "temperature": 0.7,
            "top_p": 0.9,
            "repetition_penalty": 1.1,
            "return_full_text": False,
        },
    }
    try:
        resp = requests.post(_HF_ENDPOINT, headers=headers, json=payload, timeout=60)
        resp.raise_for_status()
        data = resp.json()

        if isinstance(data, list) and data:
            first = data[0]
            text = first.get("generated_text") or first.get("text") or ""
            return text.strip() or None
        if isinstance(data, dict):
            return (data.get("generated_text") or "").strip() or None
        return None
    except RequestException as e:
        logger.error(f"HuggingFace request failed: {e}")
    except Exception as e:
        logger.error(f"Unexpected HF error: {e}")
    return None


def _call_chatbot_service(message: str, history=None) -> Optional[str]:
    """Call bla-chatbot-railway service with conversation history. Returns reply or None."""
    if not _CHATBOT_SERVICE_URL:
        return None
    history_payload = [
        {"role": h.role, "content": h.content}
        for h in (history or [])
    ]
    try:
        resp = requests.post(
            f"{_CHATBOT_SERVICE_URL}/chat",
            json={"message": message, "history": history_payload},
            timeout=90,
        )
        resp.raise_for_status()
        data = resp.json()
        return (data.get("reply") or "").strip() or None
    except RequestException as e:
        logger.error(f"Chatbot service request failed: {e}")
    except Exception as e:
        logger.error(f"Unexpected chatbot service error: {e}")
    return None


@router.post("/ai", response_model=dict)
def chat_with_ai(chat: schemas.AiChatCreate, db: Session = Depends(get_db)):
    """
    AI chatbot endpoint.

    Priority:
      1. HuggingFace Inference API  (requires HF_API_TOKEN env var)
      2. FAQ keyword search fallback
      3. Canned 'not available' message

    Returns: { "message": str, "ui_action": null }
    """
    logger.info(f"[AI_ENDPOINT] sender={chat.sender_id} message={chat.message!r}")

    try:
        history_dicts = [{"role": h.role, "content": h.content} for h in (chat.history or [])]

        # 1 — Instant answers: greetings and vague queries only (no model needed)
        instant = _instant_answer(chat.message, history_dicts)
        if instant:
            logger.info("[AI_ENDPOINT] Served instantly (greeting/clarification)")
            return {"message": instant, "ui_action": None}

        # 2 — Retrieve legal context from KB (60 topics + FAQ) to ground the model
        context = _get_legal_context(chat.message, history_dicts)

        # 3 — Send to model with context as RAG grounding
        if _CHATBOT_SERVICE_URL:
            if context:
                rag_message = (
                    f"[LEGAL CONTEXT — use this to answer accurately]\n"
                    f"{context}\n\n"
                    f"[USER QUESTION]\n{chat.message}\n\n"
                    f"Using the legal context above, provide a clear, helpful, and conversational answer. "
                    f"Cite the relevant Philippine law. Reply in the same language as the user."
                )
            else:
                rag_message = chat.message

            service_text = _call_chatbot_service(rag_message, chat.history)
            if service_text:
                log_label = "model+RAG context" if context else "model (no context)"
                logger.info(f"[AI_ENDPOINT] Served by {log_label}")
                return {"message": service_text, "ui_action": None}

        # 4 — Model unavailable: fall back to raw KB context
        if context:
            logger.info("[AI_ENDPOINT] Model unavailable — served by KB context fallback")
            return {"message": context, "ui_action": None}

        # 5 — HuggingFace Inference API (last resort before generic fallback)
        if _HF_API_TOKEN:
            hf_text = _call_hf_model(chat.message)
            if hf_text:
                logger.info("[AI_ENDPOINT] Served by HF Inference API")
                return {"message": hf_text, "ui_action": None}

        # 6 — Generic fallback
        local = _faq_fallback(sender=chat.sender_id, message=chat.message, history=history_dicts)
        return {"message": local["response"], "ui_action": None}

    except Exception as e:
        logger.error(f"Unexpected error in chat_with_ai: {e}", exc_info=True)
        return {
            "message": (
                "Sorry, I'm temporarily unavailable. "
                "Please visit your barangay hall for legal assistance."
            ),
            "ui_action": None,
        }
