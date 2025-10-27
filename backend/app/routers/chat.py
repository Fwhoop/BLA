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

@router.post("/ai", response_model=schemas.ChatRead)
def chat_with_ai(chat: schemas.ChatCreate, db: Session = Depends(get_db)):
    sender = db.query(models.User).filter(models.User.id == chat.sender_id).first()
    receiver = db.query(models.User).filter(models.User.id == chat.receiver_id).first()
    if not sender or not receiver:
        raise HTTPException(status_code=404, detail="Sender or receiver not found")

    user_chat = models.Chat(
        sender_id=chat.sender_id,
        receiver_id=chat.receiver_id,
        message=chat.message,
        created_at=datetime.utcnow()
    )
    db.add(user_chat)
    db.commit()
    db.refresh(user_chat)

    ai_response = generate_chat_response(chat.message)

    ai_chat = models.Chat(
        sender_id=chat.receiver_id,
        receiver_id=chat.sender_id,
        message=ai_response,
        created_at=datetime.utcnow(),
        is_bot=True
    )
    db.add(ai_chat)
    db.commit()
    db.refresh(ai_chat)

    return ai_chat
