from dotenv import load_dotenv
load_dotenv()  # Must run before any app imports that read env vars

from fastapi import Depends, FastAPI
from fastapi.staticfiles import StaticFiles
import os
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import inspect, text
import logging

from app.db import Base, engine
from app import models
from app.routers.auth import get_current_user
from app.models import User
from app.routers import auth, barangays, cases, chat, users, requests, notifications, mediations, analytics
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
    allow_origins=["*"],
    allow_credentials=False,
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

            # --- Cases table (new columns) ---
            if "cases" in inspector.get_table_names():
                existing_cases2 = {c["name"] for c in inspector.get_columns("cases")}
                for col, ddl in [
                    ("category",              "ALTER TABLE cases ADD COLUMN category VARCHAR(50) NULL"),
                    ("urgency",               "ALTER TABLE cases ADD COLUMN urgency VARCHAR(20) DEFAULT 'medium'"),
                    ("is_cross_barangay",     "ALTER TABLE cases ADD COLUMN is_cross_barangay BOOLEAN DEFAULT FALSE"),
                    ("complaint_barangay_id", "ALTER TABLE cases ADD COLUMN complaint_barangay_id INT NULL"),
                ]:
                    if col not in existing_cases2:
                        conn.execute(text(ddl))
                        logger.info(f"Migration: added '{col}' column to cases")

            # --- Users table ---
            if "users" in inspector.get_table_names():
                existing_users = {c["name"] for c in inspector.get_columns("users")}
                for col, ddl in [
                    ("id_photo_url",         "ALTER TABLE users ADD COLUMN id_photo_url VARCHAR(500) NULL"),
                    ("verification_status",  "ALTER TABLE users ADD COLUMN verification_status VARCHAR(30) DEFAULT 'pending_verification'"),
                    ("verification_method",  "ALTER TABLE users ADD COLUMN verification_method VARCHAR(10) DEFAULT 'email'"),
                    ("selfie_with_id_url",   "ALTER TABLE users ADD COLUMN selfie_with_id_url VARCHAR(500) NULL"),
                    ("profile_photo_url",    "ALTER TABLE users ADD COLUMN profile_photo_url VARCHAR(500) NULL"),
                    ("sms_otp_hash",         "ALTER TABLE users ADD COLUMN sms_otp_hash VARCHAR(64) NULL"),
                    ("sms_otp_expires_at",   "ALTER TABLE users ADD COLUMN sms_otp_expires_at DATETIME NULL"),
                    ("house_no",             "ALTER TABLE users ADD COLUMN house_no VARCHAR(20) NULL"),
                    ("street_name",          "ALTER TABLE users ADD COLUMN street_name VARCHAR(100) NULL"),
                    ("purok_sitio",          "ALTER TABLE users ADD COLUMN purok_sitio VARCHAR(100) NULL"),
                    ("city_municipality",    "ALTER TABLE users ADD COLUMN city_municipality VARCHAR(100) NULL"),
                    ("province",             "ALTER TABLE users ADD COLUMN province VARCHAR(100) NULL"),
                    ("zip_code",             "ALTER TABLE users ADD COLUMN zip_code VARCHAR(10) NULL"),
                    ("approved_by",          "ALTER TABLE users ADD COLUMN approved_by INT NULL"),
                    ("approved_at",          "ALTER TABLE users ADD COLUMN approved_at DATETIME NULL"),
                ]:
                    if col not in existing_users:
                        conn.execute(text(ddl))
                        logger.info(f"Migration: added '{col}' column to users")

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
app.include_router(mediations.router)
app.include_router(analytics.router)

# ----------------- Static Files -----------------
for _dir in ["uploads/id_photos", "uploads/selfie_photos", "uploads/profile_photos"]:
    os.makedirs(_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")