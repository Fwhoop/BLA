from fastapi import APIRouter, Depends, HTTPException, status, Form, UploadFile, File
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from typing import Optional
import bcrypt
import re
import os
import uuid
import secrets
import hashlib
import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from .. import models, schemas
from ..db import get_db
from ..core.config import settings

logger = logging.getLogger(__name__)


SECRET_KEY = settings.jwt_secret
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

router = APIRouter(prefix="/auth", tags=["auth"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


def verify_password(plain_password, hashed_password):
    """Verify password using bcrypt directly (compatible with Python 3.13)"""
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception as e:
        print(f"Password verification error: {e}")
        return False

def get_password_hash(password):
    """Hash password using bcrypt directly (compatible with Python 3.13)"""
    password_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

def authenticate_user(db: Session, email: str, password: str):
    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        return False
    if not verify_password(password, user.hashed_password):
        return False
    if not user.is_active:
        return "pending"
    return user

def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta if expires_delta else timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


@router.post("/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    try:
        user = authenticate_user(db, form_data.username, form_data.password)
    except Exception as e:
        print(f"Login DB error: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database unavailable. Please try again later.",
        )
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if user == "pending":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account is pending approval by the barangay admin.",
        )
    access_token = create_access_token(data={"sub": user.email},
                                       expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    return {"access_token": access_token, "token_type": "bearer"}


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials. Please login again.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}. Please login again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"User with email {email} not found. Please login again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


@router.post("/register", response_model=schemas.UserRead)
def register(
    first_name: str = Form(...),
    last_name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    phone: Optional[str] = Form(None),
    address: Optional[str] = Form(None),
    barangay: Optional[str] = Form(None),
    id_photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    """Public signup endpoint for residents."""
    # Duplicate checks
    if db.query(models.User).filter(models.User.email == email).first():
        raise HTTPException(status_code=400, detail="Email already registered")

    # Auto-generate username from email, ensure uniqueness
    base_username = re.sub(r'[^a-z0-9]', '', email.split('@')[0].lower()) or "user"
    username = base_username
    counter = 1
    while db.query(models.User).filter(models.User.username == username).first():
        username = f"{base_username}{counter}"
        counter += 1

    # Resolve barangay name → id
    barangay_id = None
    if barangay:
        brgy = db.query(models.Barangay).filter(
            models.Barangay.name == barangay
        ).first()
        if brgy:
            barangay_id = brgy.id

    # Handle ID photo upload
    id_photo_url = None
    if id_photo and id_photo.filename:
        try:
            upload_dir = os.path.join("uploads", "id_photos")
            os.makedirs(upload_dir, exist_ok=True)
            ext = id_photo.filename.rsplit('.', 1)[-1].lower() if '.' in id_photo.filename else 'jpg'
            filename = f"{uuid.uuid4().hex}.{ext}"
            file_path = os.path.join(upload_dir, filename)
            contents = id_photo.file.read()
            with open(file_path, "wb") as f:
                f.write(contents)
            id_photo_url = f"/uploads/id_photos/{filename}"
        except Exception:
            id_photo_url = None  # Don't block registration if photo save fails

    new_user = models.User(
        email=email,
        username=username,
        hashed_password=get_password_hash(password),
        first_name=first_name,
        last_name=last_name,
        phone=phone or "",
        address=address or "",
        role="user",
        barangay_id=barangay_id,
        is_active=False,  # pending admin approval
        id_photo_url=id_photo_url,
        created_at=datetime.utcnow(),
    )

    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")

    # Notify admins of the new user's barangay
    if barangay_id:
        try:
            admins = db.query(models.User).filter(
                models.User.barangay_id == barangay_id,
                models.User.role.in_(["admin", "superadmin"]),
                models.User.is_active == True,
            ).all()
            for admin in admins:
                db.add(models.Notification(
                    user_id=admin.id,
                    title="New Resident Registration",
                    message=f"{first_name} {last_name} has registered and is awaiting your approval.",
                    notif_type="new_user",
                    reference_id=new_user.id,
                ))
            if admins:
                db.commit()
        except Exception:
            pass  # Notification failure must not block registration

    return new_user


# ─── Password Reset Helpers ────────────────────────────────────────────────

def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def _generate_otp() -> str:
    """Return a 6-digit zero-padded OTP."""
    return f"{secrets.randbelow(1_000_000):06d}"


def _send_reset_email(to_email: str, first_name: str, otp: str) -> bool:
    """Send OTP via SMTP. Returns True on success, False if SMTP unconfigured."""
    host = settings.smtp_host
    username = settings.smtp_username
    password = settings.smtp_password
    port = settings.smtp_port
    from_addr = settings.smtp_from_email or username

    if not host or not username:
        return False  # SMTP not configured

    msg = MIMEMultipart("alternative")
    msg["From"] = from_addr
    msg["To"] = to_email
    msg["Subject"] = "Barangay Legal Aid – Password Reset OTP"

    body = (
        f"Hello {first_name},\n\n"
        f"Your one-time password (OTP) to reset your account password is:\n\n"
        f"    {otp}\n\n"
        f"This OTP expires in 15 minutes. Do not share it with anyone.\n\n"
        f"If you did not request a password reset, please ignore this email.\n\n"
        f"— Barangay Legal Aid System"
    )
    msg.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP(host, port, timeout=10) as server:
            server.ehlo()
            server.starttls()
            server.login(username, password)
            server.sendmail(from_addr, to_email, msg.as_string())
        return True
    except Exception as exc:
        logger.error("SMTP send failed: %s", exc)
        return False


# ─── Forgot Password Endpoints ─────────────────────────────────────────────

@router.post("/forgot-password")
def forgot_password(
    payload: schemas.ForgotPasswordRequest,
    db: Session = Depends(get_db),
):
    """
    Step 1 – Generate a 6-digit OTP and (optionally) email it.

    Always returns HTTP 200 with a generic message to prevent user enumeration.
    In development (SMTP not configured) the OTP is returned in the response
    so the feature can be tested without an email server.
    """
    user = db.query(models.User).filter(
        models.User.email == payload.email
    ).first()

    if not user:
        # Return the same response to prevent user enumeration
        return {"detail": "If that email is registered, an OTP has been sent."}

    # Invalidate any existing unused tokens for this user
    db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.user_id == user.id,
        models.PasswordResetToken.used == False,
    ).delete(synchronize_session=False)

    otp = _generate_otp()
    token_hash = _hash_token(otp)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)

    reset_token = models.PasswordResetToken(
        user_id=user.id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(reset_token)
    db.commit()

    email_sent = _send_reset_email(user.email, user.first_name, otp)

    if email_sent:
        return {"detail": "If that email is registered, an OTP has been sent."}
    else:
        # Dev/demo mode: return OTP directly (SMTP not configured)
        logger.warning("SMTP not configured – returning OTP in response (dev mode).")
        return {
            "detail": "OTP generated. (SMTP not configured – dev mode only.)",
            "dev_otp": otp,
        }


@router.post("/reset-password")
def reset_password(
    payload: schemas.ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    """
    Step 2 – Verify OTP and set a new password.
    """
    if len(payload.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="New password must be at least 8 characters.",
        )

    token_hash = _hash_token(payload.token.strip())
    now = datetime.now(timezone.utc)

    reset_record = db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.token_hash == token_hash,
        models.PasswordResetToken.used == False,
        models.PasswordResetToken.expires_at > now,
    ).first()

    if not reset_record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP.",
        )

    user = reset_record.user
    user.hashed_password = get_password_hash(payload.new_password)
    reset_record.used = True
    db.commit()

    return {"detail": "Password reset successfully. You may now log in."}
