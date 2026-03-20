from dotenv import load_dotenv
load_dotenv()

from fastapi import Depends, FastAPI, Request, UploadFile, File
import uuid
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
from app.routers import ask as ask_router          # RAG chatbot router
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

    # Load FAISS index + chunked docs for the RAG /ask endpoint
    try:
        from app.rag import load_rag_resources
        load_rag_resources()
        logger.info("RAG resources loaded successfully")
    except Exception as e:
        logger.warning(f"RAG resources could not be loaded: {e}")
        logger.warning("The /ask endpoint will be unavailable until resources are present")

    logger.info("=== BLA BACKEND READY ===")


def _backfill_users():
    """One-time data fix: mark all previously active users as approved."""
    with engine.begin() as conn:
        conn.execute(text(
            "UPDATE users SET verification_status='approved' "
            "WHERE is_active=1 AND (verification_status IS NULL OR verification_status='')"
        ))


# ── Global exception handlers ─────────────────────────────────────────────────
from fastapi.exceptions import RequestValidationError
from fastapi import HTTPException as FastAPIHTTPException
import traceback

@app.exception_handler(FastAPIHTTPException)
async def http_exception_handler(request: Request, exc: FastAPIHTTPException):
    """Return every HTTP error in consistent {success, error} shape."""
    detail = exc.detail
    if isinstance(detail, dict):
        error_msg = detail.get("error") or detail.get("detail") or str(detail)
    else:
        error_msg = str(detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": error_msg},
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Pydantic validation failures → 422 with consistent shape."""
    errors = [
        f"{' → '.join(str(l) for l in e['loc'])}: {e['msg']}"
        for e in exc.errors()
    ]
    logger.warning(f"Validation error on {request.url}: {errors}")
    return JSONResponse(
        status_code=422,
        content={"success": False, "error": "Validation failed", "fields": errors},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """
    Catch-all for unhandled exceptions.
    Logs the full stack trace server-side; returns a safe message to the client.
    """
    logger.error(
        f"Unhandled exception on {request.method} {request.url}:\n"
        + traceback.format_exc()
    )
    return JSONResponse(
        status_code=500,
        content={"success": False, "error": "An unexpected server error occurred."},
    )


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


@app.post("/auth/me/signature", response_model=UserRead)
async def upload_signature(
    file: UploadFile = File(...),
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Admin uploads or replaces their digital signature image."""
    _sig_dir = "uploads/signatures"
    os.makedirs(_sig_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "signature.png")[1] or ".png"
    fname = f"sig_{current.id}_{uuid.uuid4().hex[:8]}{ext}"
    fpath = os.path.join(_sig_dir, fname)
    contents = await file.read()
    with open(fpath, "wb") as f:
        f.write(contents)
    current.signature_path = f"/uploads/signatures/{fname}"
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
app.include_router(ask_router.router)   # POST /ask  – RAG chatbot


# ── Static Files (ID photos, selfies, profile photos) ────────────────────────
try:
    for _dir in ["uploads/id_photos", "uploads/documents", "uploads/resolution_photos", "uploads/logos", "uploads/signatures"]:
        os.makedirs(_dir, exist_ok=True)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
except Exception as e:
    logger.warning(f"Static files not mounted: {e}")
