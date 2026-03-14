from dotenv import load_dotenv
load_dotenv()  # Must run before any app imports that read env vars

from fastapi import Depends, FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
import os
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import inspect, text
import logging

from app.db import Base, engine
from app import models
from app.routers.auth import get_current_user
from app.models import User
from app.routers import auth, barangays, cases, chat, users, requests, notifications
from app.schemas import UserRead


# ----------------- Logging -----------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
logging.getLogger('python_multipart').setLevel(logging.WARNING)

# ----------------- App -----------------
app = FastAPI(title="Barangay Legal Aid API", version="0.1.0")
load_dotenv()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict this in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------- Migrations -----------------
def _run_migrations():
    """
    Add missing columns if they don’t exist (safe to run on every startup).
    """
    try:
        inspector = inspect(engine)
        with engine.begin() as conn:  # BEGIN ensures auto-commit on DDL
            # --- Cases table ---
            if "cases" in inspector.get_table_names():
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

            # --- Users table ---
            if "users" in inspector.get_table_names():
                existing_users = {c["name"] for c in inspector.get_columns("users")}
                if "id_photo_url" not in existing_users:
                    conn.execute(text(
                        "ALTER TABLE users ADD COLUMN id_photo_url VARCHAR(500) NULL"
                    ))
                    logger.info("Migration: added 'id_photo_url' column to users")

    except Exception as e:
        logger.warning(f"Migration step skipped: {e}")

# ----------------- Startup Event -----------------
@app.on_event("startup")
async def create_tables():
    """
    Ensure all tables exist and run migrations.
    This runs every time the app starts (Railway or local).
    """
    try:
        # This will create all tables that don’t exist yet
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created/verified successfully")
        _run_migrations()
        logger.info("Migrations complete")
    except Exception as e:
        logger.warning(f"Could not create database tables: {e}")
        logger.warning("Server will continue, but database operations may fail until connection is fixed")

# ----------------- One-time Reset Endpoint (REMOVE AFTER USE) -----------------
@app.get("/reset-bla-xk9q2")
def reset_all_users():
    """Wipe all users and create a fresh superadmin. DELETE THIS AFTER USE."""
    import bcrypt
    from datetime import datetime, timezone
    from app.db import SessionLocal
    from app.models import User, Notification, Chat, Case, Request

    db = SessionLocal()
    try:
        db.query(Notification).delete()
        db.query(Chat).delete()
        db.query(Case).delete()
        db.query(Request).delete()
        db.query(User).delete()
        pw = bcrypt.hashpw(b"SuperAdmin@2024", bcrypt.gensalt()).decode("utf-8")
        db.add(User(
            email="superadmin@bla.com",
            username="superadmin",
            hashed_password=pw,
            first_name="Super",
            last_name="Admin",
            role="superadmin",
            barangay_id=None,
            is_active=True,
            created_at=datetime.now(timezone.utc),
        ))
        db.commit()
        return {
            "status": "done",
            "email": "superadmin@bla.com",
            "password": "SuperAdmin@2024",
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        db.close()

# ----------------- Auth Route -----------------
@app.get("/auth/me", response_model=UserRead)
async def me(current: User = Depends(get_current_user)):
    if current.is_active is None:
        current.is_active = True
    return current

# ----------------- Routers -----------------
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(barangays.router)
app.include_router(cases.router)
app.include_router(chat.router)
app.include_router(requests.router)
app.include_router(notifications.router)

# ----------------- Static Files -----------------
os.makedirs("uploads/id_photos", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")