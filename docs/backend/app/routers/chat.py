from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from .. import models, schemas
from ..db import get_db
from ..chatbot import load_faq_data

import os
import logging
import requests
from requests import RequestException, Timeout

logger = logging.getLogger(__name__)

# Model backend URL — override via env var or defaults to the Railway deployment
_MODEL_URL = os.environ.get(
    "CHATBOT_SERVICE_URL",
    "https://bla-chatbot-railway-production.up.railway.app",
).rstrip("/")

_MODEL_TIMEOUT = int(os.environ.get("MODEL_TIMEOUT_SECONDS", "90"))

_FALLBACK_MESSAGE = (
    "I'm sorry, I'm unable to reach the AI service right now. "
    "Please try again in a moment, or visit your barangay hall for legal assistance."
)

router = APIRouter(prefix="/chats", tags=["chats"])


# ── CRUD endpoints ─────────────────────────────────────────────────────────────

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


# ── AI endpoint ────────────────────────────────────────────────────────────────

@router.post("/ai", response_model=dict)
def chat_with_ai(chat: schemas.AiChatCreate, db: Session = Depends(get_db)):
    """
    Forward the user's message and conversation history to the model backend,
    then return its reply to the frontend.

    Falls back to a static message if the model backend is unreachable or
    returns an error.
    """
    logger.info(f"[/chats/ai] sender={chat.sender_id} message={chat.message!r}")

    history_payload = [
        {"role": h.role, "content": h.content}
        for h in (chat.history or [])
    ]

    target_url = f"{_MODEL_URL}/chat"

    try:
        resp = requests.post(
            target_url,
            json={"message": chat.message, "history": history_payload},
            timeout=_MODEL_TIMEOUT,
        )
        resp.raise_for_status()

        data = resp.json()
        reply = (data.get("reply") or "").strip()

        if not reply:
            logger.warning(f"[/chats/ai] Model returned empty reply — using fallback")
            return {"message": _FALLBACK_MESSAGE, "ui_action": None}

        logger.info(f"[/chats/ai] Model replied ({len(reply)} chars)")
        return {"message": reply, "ui_action": None}

    except Timeout:
        logger.error(f"[/chats/ai] Timed out after {_MODEL_TIMEOUT}s calling {target_url}")
    except RequestException as e:
        logger.error(f"[/chats/ai] Request to model backend failed: {e}")
    except Exception as e:
        logger.error(f"[/chats/ai] Unexpected error: {e}", exc_info=True)

    return {"message": _FALLBACK_MESSAGE, "ui_action": None}
