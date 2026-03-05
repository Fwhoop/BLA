from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from .. import models, schemas
from ..db import get_db
from ..chatbot import generate_chat_response, load_faq_data, chat_response as _local_chat_response

import os
import logging
import requests
from requests import RequestException

# environment settings used for HF inference
_HF_API_TOKEN = os.environ.get("HF_API_TOKEN", "")
_HF_MODEL_ID = os.environ.get("HF_MODEL_ID", "fwhoop/bla_model")
_HF_ENDPOINT = f"https://api-inference.huggingface.co/models/{_HF_MODEL_ID}"

router = APIRouter(prefix="/chats", tags=["chats"])

@router.post("/", response_model=schemas.ChatRead)
def create_chat(chat: schemas.ChatCreate, db: Session = Depends(get_db)):
    sender = db.query(models.User).filter(models.User.id == chat.sender_id).first()
    receiver = db.query(models.User).filter(models.User.id == chat.receiver_id).first()
    if not sender or not receiver:
        raise HTTPException(status_code=404, detail="Sender or receiver not found")

    new_chat = models.Chat(
        sender_id=chat.sender_id,
        receiver_id=chat.receiver_id,
        message=chat.message,
        created_at=datetime.utcnow()
    )
    db.add(new_chat)
    db.commit()
    db.refresh(new_chat)
    return new_chat

@router.get("/", response_model=List[schemas.ChatRead])
def get_all_chats(db: Session = Depends(get_db)):
    return db.query(models.Chat).all()

@router.get("/{chat_id}", response_model=schemas.ChatRead)
def get_chat(chat_id: int, db: Session = Depends(get_db)):
    chat = db.query(models.Chat).filter(models.Chat.id == chat_id).first()
    if not chat:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found")
    return chat

@router.get("/faq")
def get_faq_data():
    """Get FAQ data (categories and questions)"""
    try:
        faq_data = load_faq_data()
        if faq_data is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="FAQ data not available"
            )
        return faq_data
    except Exception as e:
        logger = logging.getLogger(__name__)
        logger.error(f"Error loading FAQ data: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to load FAQ data: {str(e)}"
        )


def _call_hf_model(prompt: str, logger: logging.Logger) -> Optional[str]:
    """Send a prompt to the HuggingFace inference API and return the generated text.

    Returns None on failure; caller should fall back as needed.
    """
    if not _HF_API_TOKEN:
        logger.debug("No HF_API_TOKEN set, skipping HF model call")
        return None

    headers = {"Authorization": f"Bearer {_HF_API_TOKEN}"}
    payload = {"inputs": prompt}
    try:
        logger.debug(f"HF request → endpoint={_HF_ENDPOINT} payload={payload}")
        resp = requests.post(_HF_ENDPOINT, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        logger.debug(f"HF response status={resp.status_code} body={resp.text}")
        data = resp.json()

        # inference API sometimes returns a list of dictionaries
        if isinstance(data, list) and data:
            first = data[0]
            return first.get("generated_text") or first.get("text") or str(data)
        if isinstance(data, dict) and "generated_text" in data:
            return data["generated_text"]
        return str(data)
    except RequestException as re:
        logger.error(f"HuggingFace request failed: {re}", exc_info=True)
    except Exception as e:
        logger.error(f"Unexpected error calling HF inference: {e}", exc_info=True)
    return None

@router.post("/ai", response_model=dict)
def chat_with_ai(chat: schemas.AiChatCreate, db: Session = Depends(get_db)):
    """
    AI chatbot endpoint powered by the locally-loaded BLA model.

    Accepts:
        {
          "sender_id": int,
          "receiver_id": int,
          "message": str,
          "history": [{"role": "user"|"bot", "content": str}, ...]  // optional
        }

    Returns:
        { "response": str, "enriched": str, "sender": int }

    The model is loaded once at startup from the local bla_model directory.
    No Hugging Face online calls are made.
    """
    logger = logging.getLogger(__name__)

    logger.info(
        f"[AI_ENDPOINT] sender={chat.sender_id} "
        f"history_len={len(chat.history or [])} "
        f"message={chat.message!r}"
    )

    try:
        # Convert Pydantic HistoryEntry objects → plain dicts the chatbot expects.
        history = [h.model_dump() for h in (chat.history or [])]

        return _local_chat_response(
            sender=chat.sender_id,
            message=chat.message,
            history=history,
        )
    except Exception as e:
        logger.error(f"Unexpected error in chat_with_ai: {e}", exc_info=True)
        return {"error": "Internal server error"}
