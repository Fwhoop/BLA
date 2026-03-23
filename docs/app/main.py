from dotenv import load_dotenv
load_dotenv()  # Must run before any app imports that read env vars

from fastapi import Depends, FastAPI, HTTPException
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
from app.routers import auth, barangays, cases, chat, users, requests
from app.schemas import UserRead

app = FastAPI(title="Barangay Legal Aid API", version="0.1.0")

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
            existing = {c["name"] for c in inspector.get_columns("cases")}
            if "status" not in existing:
                conn.execute(text(
                    "ALTER TABLE cases ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending'"
                ))
                logger.info("Migration: added 'status' column to cases")
            if "updated_at" not in existing:
                conn.execute(text(
                    "ALTER TABLE cases ADD COLUMN updated_at DATETIME "
                    "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
                ))
                logger.info("Migration: added 'updated_at' column to cases")
            conn.commit()
    except Exception as e:
        logger.warning(f"Migration step skipped (cases table may not exist yet): {e}")


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

# ONE-TIME RESET — DELETE AFTER USE
@app.get("/reset-bla-xk9q2")
def reset_all_users():
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
        return {"status": "done", "email": "superadmin@bla.com", "password": "SuperAdmin@2024"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        db.close()
