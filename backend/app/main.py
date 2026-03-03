from dotenv import load_dotenv
load_dotenv()  # Must run before any app imports that read env vars

from fastapi import Depends, FastAPI
from fastapi.staticfiles import StaticFiles
import os
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import inspect, text
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
from app.routers import auth, barangays, cases, chat, users, requests, notifications
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

def _run_migrations():
    """Add any missing columns to existing tables (safe to run on every startup)."""
    try:
        inspector = inspect(engine)
        with engine.connect() as conn:
            existing_cases = {c["name"] for c in inspector.get_columns("cases")}
            if "status" not in existing_cases:
                conn.execute(text(
                    "ALTER TABLE cases ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending'"
                ))
                logger.info("Migration: added 'status' column to cases")
            if "updated_at" not in existing_cases:
                conn.execute(text(
                    "ALTER TABLE cases ADD COLUMN updated_at DATETIME "
                    "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
                ))
                logger.info("Migration: added 'updated_at' column to cases")

            existing_users = {c["name"] for c in inspector.get_columns("users")}
            if "id_photo_url" not in existing_users:
                conn.execute(text(
                    "ALTER TABLE users ADD COLUMN id_photo_url VARCHAR(500) NULL"
                ))
                logger.info("Migration: added 'id_photo_url' column to users")

            conn.commit()
    except Exception as e:
        logger.warning(f"Migration step skipped: {e}")


# Create database tables on startup (with error handling)
@app.on_event("startup")
async def create_tables():
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created/verified successfully")
        _run_migrations()
    except Exception as e:
        logger.warning(f"Could not create database tables: {e}")
        logger.warning("Server will continue, but database operations may fail until connection is fixed")

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
app.include_router(notifications.router)

# Serve uploaded files (ID photos, etc.) — must come AFTER all routers
os.makedirs("uploads/id_photos", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
