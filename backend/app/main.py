from fastapi import Depends, FastAPI
from dotenv import load_dotenv
import os
from fastapi.middleware.cors import CORSMiddleware
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Reduce noise from multipart parser
logging.getLogger('python_multipart').setLevel(logging.WARNING)

from app.db import Base, engine
from app.routers.auth import get_current_user
from app.models import User
from app.routers import auth, barangays, cases, chat, users, requests
from app.schemas import UserRead

app = FastAPI(title="Barangay Legal Aid API", version="0.1.0")

load_dotenv()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)

@app.get("/auth/me", response_model=UserRead)
async def me(current: User = Depends(get_current_user)):
    # Ensure is_active is a boolean, not None
    if current.is_active is None:
        current.is_active = True
    return current

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(barangays.router)
app.include_router(cases.router)
app.include_router(chat.router)
app.include_router(requests.router)
