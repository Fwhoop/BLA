from dotenv import load_dotenv
load_dotenv()

from fastapi import Depends, FastAPI
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import inspect, text
import os
import logging

from app.db import Base, engine, get_db
from app import models
from app.routers.auth import get_current_user
from app.models import User
from app.routers import auth, barangays, cases, chat, users, requests, notifications
from app.routers import respondents, mediations, analytics
from app.schemas import UserRead, UserUpdate
from sqlalchemy.orm import Session

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
logging.getLogger('python_multipart').setLevel(logging.WARNING)

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="Barangay Legal Aid API", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Migrations ────────────────────────────────────────────────────────────────
def _run_migrations():
    """Idempotent migrations — safe to run on every startup."""
    try:
        inspector = inspect(engine)
        table_names = inspector.get_table_names()

        with engine.begin() as conn:
            # ── cases table ──────────────────────────────────────────────────
            if "cases" in table_names:
                existing = {c["name"] for c in inspector.get_columns("cases")}
                for col, ddl in [
                    ("status",                "ALTER TABLE cases ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending'"),
                    ("updated_at",            "ALTER TABLE cases ADD COLUMN updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"),
                    ("category",              "ALTER TABLE cases ADD COLUMN category VARCHAR(50) NULL"),
                    ("urgency",               "ALTER TABLE cases ADD COLUMN urgency VARCHAR(20) DEFAULT 'medium'"),
                    ("is_cross_barangay",     "ALTER TABLE cases ADD COLUMN is_cross_barangay BOOLEAN DEFAULT FALSE"),
                    ("complaint_barangay_id", "ALTER TABLE cases ADD COLUMN complaint_barangay_id INT NULL"),
                ]:
                    if col not in existing:
                        conn.execute(text(ddl))
                        logger.info(f"Migration: added '{col}' to cases")

            # ── users table ──────────────────────────────────────────────────
            if "users" in table_names:
                existing = {c["name"] for c in inspector.get_columns("users")}
                for col, ddl in [
                    ("id_photo_url",        "ALTER TABLE users ADD COLUMN id_photo_url VARCHAR(500) NULL"),
                    ("selfie_with_id_path", "ALTER TABLE users ADD COLUMN selfie_with_id_path VARCHAR(500) NULL"),
                    ("profile_photo_path",  "ALTER TABLE users ADD COLUMN profile_photo_path VARCHAR(500) NULL"),
                    ("verification_status", "ALTER TABLE users ADD COLUMN verification_status VARCHAR(20) DEFAULT 'pending'"),
                    ("verification_method", "ALTER TABLE users ADD COLUMN verification_method VARCHAR(50) NULL"),
                    ("email_verified",      "ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE"),
                    ("mobile_verified",     "ALTER TABLE users ADD COLUMN mobile_verified BOOLEAN DEFAULT FALSE"),
                    ("approved_by",         "ALTER TABLE users ADD COLUMN approved_by INT NULL"),
                    ("approved_at",         "ALTER TABLE users ADD COLUMN approved_at DATETIME NULL"),
                    ("house_number",        "ALTER TABLE users ADD COLUMN house_number VARCHAR(50) NULL"),
                    ("street_name",         "ALTER TABLE users ADD COLUMN street_name VARCHAR(100) NULL"),
                    ("purok",               "ALTER TABLE users ADD COLUMN purok VARCHAR(50) NULL"),
                    ("city",                "ALTER TABLE users ADD COLUMN city VARCHAR(100) NULL"),
                    ("province",            "ALTER TABLE users ADD COLUMN province VARCHAR(100) NULL"),
                    ("zip_code",            "ALTER TABLE users ADD COLUMN zip_code VARCHAR(10) NULL"),
                ]:
                    if col not in existing:
                        conn.execute(text(ddl))
                        logger.info(f"Migration: added '{col}' to users")

                # Backfill verification_status for existing approved users
                conn.execute(text(
                    "UPDATE users SET verification_status='approved' "
                    "WHERE is_active=1 AND (verification_status IS NULL OR verification_status='')"
                ))

            # ── requests table ───────────────────────────────────────────────
            if "requests" in table_names:
                existing = {c["name"] for c in inspector.get_columns("requests")}
                for col, ddl in [
                    ("file_url", "ALTER TABLE requests ADD COLUMN file_url VARCHAR(500) NULL"),
                ]:
                    if col not in existing:
                        conn.execute(text(ddl))
                        logger.info(f"Migration: added '{col}' to requests")

            # ── mediations table ─────────────────────────────────────────────
            if "mediations" in table_names:
                existing = {c["name"] for c in inspector.get_columns("mediations")}
                for col, ddl in [
                    ("mediator_name",         "ALTER TABLE mediations ADD COLUMN mediator_name VARCHAR(200) NULL"),
                    ("resolution_photo_path", "ALTER TABLE mediations ADD COLUMN resolution_photo_path VARCHAR(500) NULL"),
                ]:
                    if col not in existing:
                        conn.execute(text(ddl))
                        logger.info(f"Migration: added '{col}' to mediations")

    except Exception as e:
        logger.warning(f"Migration step skipped: {e}")


# ── Startup ───────────────────────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    logger.info("=== BLA BACKEND STARTING ===")
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables OK")
        _run_migrations()
        logger.info("Migrations OK")
    except Exception as e:
        logger.warning(f"DB init skipped: {e}")
    logger.info("=== BLA BACKEND READY ===")


# ── Health ────────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok", "service": "BLA Backend"}

@app.get("/")
async def root():
    return {"status": "ok", "service": "Barangay Legal Aid API"}


# ── Auth/Me Routes ────────────────────────────────────────────────────────────
@app.get("/auth/me", response_model=UserRead)
async def me(current: User = Depends(get_current_user)):
    if current.is_active is None:
        current.is_active = True
    return current

@app.put("/auth/me", response_model=UserRead)
async def update_me(
    payload: UserUpdate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(current, field, value)
    db.commit()
    db.refresh(current)
    return current


# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(barangays.router)
app.include_router(cases.router)
app.include_router(chat.router)
app.include_router(requests.router)
app.include_router(notifications.router)
app.include_router(respondents.router)
app.include_router(mediations.router)
app.include_router(analytics.router)


# ── Static Files (ID photos, selfies, profile photos) ────────────────────────
try:
    for _dir in ["uploads/id_photos", "uploads/documents", "uploads/resolution_photos"]:
        os.makedirs(_dir, exist_ok=True)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
except Exception as e:
    logger.warning(f"Static files not mounted: {e}")
