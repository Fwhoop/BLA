from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from .. import models, schemas
from ..db import get_db
from ..chatbot import generate_chat_response, load_faq_data

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
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"Error loading FAQ data: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to load FAQ data: {str(e)}"
        )

@router.post("/ai", response_model=dict)
def chat_with_ai(chat: schemas.AiChatCreate, db: Session = Depends(get_db)):
    """
    AI chatbot endpoint — intent-routed with conversation history support.
    Returns: { message, ui_action, sender_id, receiver_id }
    """
    import logging
    logger = logging.getLogger(__name__)

    try:
        logger.info(f"AI chat: sender={chat.sender_id} message={chat.message!r}")

        history = [{"role": h.role, "content": h.content} for h in (chat.history or [])]

        message, ui_action = generate_chat_response(chat.message, history)
        logger.info(f"Response → ui_action={ui_action!r}")

        return {
            "message": message,
            "ui_action": ui_action,
            "sender_id": chat.sender_id,
            "receiver_id": chat.receiver_id,
        }
    except Exception as e:
        logger.error(f"Unexpected error in chat_with_ai: {e}", exc_info=True)
        return {
            "message": "I apologize, but I encountered an error. Please try again or contact the barangay office directly.",
            "ui_action": None,
            "sender_id": chat.sender_id,
            "receiver_id": chat.receiver_id,
        }
