from dotenv import load_dotenv
load_dotenv()

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
import os
import logging

from app.db import Base, engine, get_db
from app import models
from app.routers.auth import get_current_user
from app.models import User
from app.routers import auth, barangays, cases, chat, users, requests, notifications
from app.routers import respondents, mediations, analytics
from app.schemas import UserRead, UserUpdate
from app.utils.db_ready import wait_for_database
from app.utils.schema_guard import validate_schema
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


# ── Startup ───────────────────────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    logger.info("=== BLA BACKEND STARTING ===")
    import asyncio
    loop = asyncio.get_event_loop()

    def _init_db():
        # Step 1 — wait for DB to accept connections
        wait_for_database(max_retries=30, delay=2.0)

        # Step 2 — create any tables that don't exist yet
        try:
            Base.metadata.create_all(bind=engine)
            logger.info("Database tables OK")
        except Exception as e:
            logger.warning(f"create_all skipped: {e}")

        # Step 3 — idempotent column migrations + schema drift repair
        try:
            _backfill_users()
        except Exception as e:
            logger.warning(f"Users backfill skipped: {e}")

        validate_schema()
        logger.info("Schema validation OK")

    await loop.run_in_executor(None, _init_db)
    logger.info("=== BLA BACKEND READY ===")


def _backfill_users():
    """One-time data fix: mark all previously active users as approved."""
    with engine.begin() as conn:
        conn.execute(text(
            "UPDATE users SET verification_status='approved' "
            "WHERE is_active=1 AND (verification_status IS NULL OR verification_status='')"
        ))


# ── Global DB error handler ───────────────────────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    import pymysql
    if isinstance(exc, pymysql.err.OperationalError):
        logger.error(f"DB OperationalError on {request.url}: {exc}")
        return JSONResponse(
            status_code=503,
            content={"detail": "Database error — please try again shortly."},
        )
    # Re-raise anything else so FastAPI's default handler runs
    raise exc


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
