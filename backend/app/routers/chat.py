from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from .. import models, schemas
from ..db import get_db
from ..chatbot import generate_chat_response

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

@router.post("/ai", response_model=dict)
def chat_with_ai(chat: schemas.ChatCreate, db: Session = Depends(get_db)):
    """
    Simple AI endpoint that returns the response directly without saving to database.
    """
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        logger.info(f"Received chat request: sender_id={chat.sender_id}, message={chat.message}")
        
        logger.info("Generating AI response...")
        
        try:
            ai_response = generate_chat_response(chat.message)
            logger.info(f"Generated response: {ai_response[:50]}...")
        except Exception as ai_error:
            logger.error(f"Error generating AI response: {ai_error}")
            ai_response = f"Thank you for your message: '{chat.message}'. I'm the Barangay Legal Aid chatbot. Please contact the barangay office directly for assistance."
        
        return {
            "message": ai_response,
            "sender_id": chat.sender_id,
            "receiver_id": getattr(chat, 'receiver_id', 1)
        }
    except Exception as e:
        logger.error(f"Unexpected error in chat_with_ai: {str(e)}", exc_info=True)
        return {
            "message": "I apologize, but I encountered an error. Please try again or contact the barangay office directly.",
            "sender_id": chat.sender_id,
            "receiver_id": getattr(chat, 'receiver_id', 1)
        }
