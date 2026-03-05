from dotenv import load_dotenv
load_dotenv()

from fastapi import Depends, FastAPI, Request
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
from app.schemas import UserRead, UserUpdate
from sqlalchemy.orm import Session

# ----------------- Logging -----------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
logging.getLogger('python_multipart').setLevel(logging.WARNING)

# ----------------- App -----------------
app = FastAPI(title="Barangay Legal Aid API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------- Migrations -----------------
def _run_migrations():
    try:
        inspector = inspect(engine)
        with engine.begin() as conn:
            if "cases" in inspector.get_table_names():
                existing = {c["name"] for c in inspector.get_columns("cases")}
                if "status" not in existing:
                    conn.execute(text("ALTER TABLE cases ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending'"))
                if "updated_at" not in existing:
                    conn.execute(text("ALTER TABLE cases ADD COLUMN updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"))
                for col, ddl in [
                    ("category",              "ALTER TABLE cases ADD COLUMN category VARCHAR(50) NULL"),
                    ("urgency",               "ALTER TABLE cases ADD COLUMN urgency VARCHAR(20) DEFAULT 'medium'"),
                    ("is_cross_barangay",     "ALTER TABLE cases ADD COLUMN is_cross_barangay BOOLEAN DEFAULT FALSE"),
                    ("complaint_barangay_id", "ALTER TABLE cases ADD COLUMN complaint_barangay_id INT NULL"),
                ]:
                    if col not in existing:
                        conn.execute(text(ddl))

            if "users" in inspector.get_table_names():
                existing = {c["name"] for c in inspector.get_columns("users")}
                for col, ddl in [
                    ("id_photo_url", "ALTER TABLE users ADD COLUMN id_photo_url VARCHAR(500) NULL"),
                ]:
                    if col not in existing:
                        conn.execute(text(ddl))
    except Exception as e:
        logger.warning(f"Migration step skipped: {e}")

# ----------------- Startup -----------------
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

# ----------------- Health / Root -----------------
@app.get("/health")
async def health():
    return {"status": "ok", "service": "BLA Backend"}

@app.get("/")
async def root():
    return {"status": "ok", "service": "Barangay Legal Aid API"}

# ----------------- Auth Routes -----------------
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

# ----------------- Routers -----------------
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(barangays.router)
app.include_router(cases.router)
app.include_router(chat.router)
app.include_router(requests.router)
app.include_router(notifications.router)

# ----------------- Static Files -----------------
try:
    for _dir in ["uploads/id_photos"]:
        os.makedirs(_dir, exist_ok=True)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
except Exception as e:
    logger.warning(f"Static files not mounted: {e}")
