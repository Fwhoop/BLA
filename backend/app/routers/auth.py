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


# ── Password helpers ──────────────────────────────────────────────────────────

def verify_password(plain_password, hashed_password):
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception as e:
        logger.error("Password verification error: %s", e)
        return False


def get_password_hash(password):
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def _generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


# ── File upload helper ────────────────────────────────────────────────────────

_ALLOWED_IMAGE_TYPES = {"jpg", "jpeg", "png", "webp", "gif"}
_MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # 5 MB


def _save_upload(upload: Optional[UploadFile], subfolder: str) -> Optional[str]:
    """Save an uploaded file after type+size validation. Returns URL path or None."""
    if not upload or not upload.filename:
        return None
    try:
        ext = upload.filename.rsplit('.', 1)[-1].lower() if '.' in upload.filename else ''
        if ext not in _ALLOWED_IMAGE_TYPES:
            logger.warning("Rejected upload: unsupported type '.%s'", ext)
            return None
        data = upload.file.read()
        if len(data) > _MAX_UPLOAD_BYTES:
            logger.warning("Rejected upload: file too large (%d bytes)", len(data))
            return None
        upload_dir = os.path.join("uploads", subfolder)
        os.makedirs(upload_dir, exist_ok=True)
        filename = f"{uuid.uuid4().hex}.{ext}"
        file_path = os.path.join(upload_dir, filename)
        with open(file_path, "wb") as f:
            f.write(data)
        return f"/uploads/{subfolder}/{filename}"
    except Exception as exc:
        logger.error("File upload failed: %s", exc)
        return None


# ── SMTP helper ───────────────────────────────────────────────────────────────

def _send_email(to_email: str, subject: str, body: str) -> bool:
    host = settings.smtp_host
    username = settings.smtp_username
    password = settings.smtp_password
    port = settings.smtp_port
    from_addr = settings.smtp_from_email or username
    if not host or not username:
        return False
    msg = MIMEMultipart("alternative")
    msg["From"] = from_addr
    msg["To"] = to_email
    msg["Subject"] = subject
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


# ── JWT helpers ───────────────────────────────────────────────────────────────

def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def authenticate_user(db: Session, identifier: str, password: str):
    """Authenticate by email or phone."""
    user = db.query(models.User).filter(
        (models.User.email == identifier) | (models.User.phone == identifier)
    ).first()
    if not user or not verify_password(password, user.hashed_password):
        return False
    if user.verification_status == "rejected":
        return "rejected"
    if user.verification_status == "pending_verification":
        return "pending"
    return user


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials. Please login again.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        identifier: str = payload.get("sub")
        if identifier is None:
            raise credentials_exception
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}. Please login again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = db.query(models.User).filter(
        (models.User.email == identifier) | (models.User.phone == identifier)
    ).first()
    if user is None:
        raise credentials_exception
    return user


# ── Login ─────────────────────────────────────────────────────────────────────

@router.post("/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    try:
        user = authenticate_user(db, form_data.username, form_data.password)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database unavailable. Please try again later.",
        )
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if user == "rejected":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has been rejected. Please contact the barangay.",
        )
    if user == "pending":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account is pending admin verification. Please wait for approval.",
        )
    identifier = user.email or user.phone
    access_token = create_access_token(
        data={"sub": identifier},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    return {"access_token": access_token, "token_type": "bearer"}


# ── Register ──────────────────────────────────────────────────────────────────

@router.post("/register", response_model=schemas.UserRead)
def register(
    first_name: str = Form(...),
    last_name: str = Form(...),
    email: Optional[str] = Form(None),
    password: str = Form(...),
    phone: Optional[str] = Form(None),
    verification_method: str = Form("email"),   # "email" | "sms"
    barangay: Optional[str] = Form(None),
    # address fields
    address: Optional[str] = Form(None),
    house_no: Optional[str] = Form(None),
    street_name: Optional[str] = Form(None),
    purok_sitio: Optional[str] = Form(None),
    city_municipality: Optional[str] = Form(None),
    province: Optional[str] = Form(None),
    zip_code: Optional[str] = Form(None),
    # file uploads
    id_photo: Optional[UploadFile] = File(None),
    selfie_with_id: Optional[UploadFile] = File(None),
    profile_photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    """Public signup endpoint — supports email or SMS-only registration."""

    # ── Validation ──────────────────────────────────────────────────────────
    if verification_method == "email":
        if not email:
            raise HTTPException(status_code=400, detail="Email is required for email verification.")
    elif verification_method == "sms":
        if not phone:
            raise HTTPException(status_code=400, detail="Phone number is required for SMS verification.")
    else:
        raise HTTPException(status_code=400, detail="verification_method must be 'email' or 'sms'.")

    if email:
        if db.query(models.User).filter(models.User.email == email).first():
            raise HTTPException(status_code=400, detail="Email already registered.")
    if phone:
        existing_phone = db.query(models.User).filter(models.User.phone == phone).first()
        if existing_phone:
            raise HTTPException(status_code=400, detail="Phone number already registered.")

    # ── Username generation ──────────────────────────────────────────────────
    base = re.sub(r'[^a-z0-9]', '', (email or phone or "user").split('@')[0].lower()) or "user"
    username, counter = base, 1
    while db.query(models.User).filter(models.User.username == username).first():
        username = f"{base}{counter}"
        counter += 1

    # ── Barangay lookup ──────────────────────────────────────────────────────
    barangay_id = None
    if barangay:
        brgy = db.query(models.Barangay).filter(models.Barangay.name == barangay).first()
        if brgy:
            barangay_id = brgy.id

    # ── File uploads ─────────────────────────────────────────────────────────
    id_photo_url = _save_upload(id_photo, "id_photos")
    selfie_with_id_url = _save_upload(selfie_with_id, "selfies")
    profile_photo_url = _save_upload(profile_photo, "profiles")

    # ── SMS OTP (dev mode) ───────────────────────────────────────────────────
    sms_otp = None
    sms_otp_hash = None
    sms_otp_expires_at = None
    if verification_method == "sms":
        sms_otp = _generate_otp()
        sms_otp_hash = _hash_token(sms_otp)
        sms_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)

    new_user = models.User(
        email=email,
        username=username,
        hashed_password=get_password_hash(password),
        first_name=first_name,
        last_name=last_name,
        phone=phone,
        verification_method=verification_method,
        verification_status="pending_verification",
        is_active=False,
        barangay_id=barangay_id,
        id_photo_url=id_photo_url,
        selfie_with_id_url=selfie_with_id_url,
        profile_photo_url=profile_photo_url,
        sms_otp_hash=sms_otp_hash,
        sms_otp_expires_at=sms_otp_expires_at,
        address=address,
        house_no=house_no,
        street_name=street_name,
        purok_sitio=purok_sitio,
        city_municipality=city_municipality,
        province=province,
        zip_code=zip_code,
    )

    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")

    # ── Email verification (dev: return token) ───────────────────────────────
    email_verify_token = None
    if verification_method == "email" and email:
        ev_otp = _generate_otp()
        email_verify_token = ev_otp
        # Store in PasswordResetToken table (reuse pattern, type="email_verify")
        db.add(models.PasswordResetToken(
            user_id=new_user.id,
            token_hash=_hash_token(ev_otp),
            expires_at=datetime.now(timezone.utc) + timedelta(hours=24),
        ))
        db.commit()
        _send_email(
            email,
            "Barangay Legal Aid – Verify Your Account",
            f"Hello {first_name},\n\nYour verification OTP is: {ev_otp}\n\nThis expires in 24 hours.\n\n— Barangay Legal Aid"
        )

    # ── Notify admins ────────────────────────────────────────────────────────
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
                    message=f"{first_name} {last_name} has registered and is awaiting ID verification.",
                    notif_type="new_user",
                    reference_id=new_user.id,
                ))
            if admins:
                db.commit()
        except Exception:
            pass

    # Build response — include dev tokens if SMTP not configured
    response = schemas.UserRead.model_validate(new_user)
    result = response.model_dump()
    if sms_otp:
        result["dev_sms_otp"] = sms_otp
    if email_verify_token and not settings.smtp_host:
        result["dev_email_otp"] = email_verify_token
    return result


# ── Admin: Approve / Reject user ─────────────────────────────────────────────

@router.put("/approve-user/{user_id}", response_model=schemas.UserRead)
def approve_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(status_code=403, detail="Only admins can approve users.")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if current_user.role == "admin" and user.barangay_id != current_user.barangay_id:
        raise HTTPException(status_code=403, detail="Cannot approve users from another barangay.")
    user.verification_status = "approved"
    user.is_active = True
    user.approved_by = current_user.id
    user.approved_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(user)
    return user


@router.put("/reject-user/{user_id}", response_model=schemas.UserRead)
def reject_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(status_code=403, detail="Only admins can reject users.")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if current_user.role == "admin" and user.barangay_id != current_user.barangay_id:
        raise HTTPException(status_code=403, detail="Cannot reject users from another barangay.")
    user.verification_status = "rejected"
    user.is_active = False
    db.commit()
    db.refresh(user)
    return user


# ── Verify SMS OTP ────────────────────────────────────────────────────────────

_sms_attempt_cache: dict = {}   # phone -> (count, window_start) — simple in-memory rate limit

@router.post("/verify-sms")
def verify_sms(
    phone: str = Form(...),
    otp: str = Form(...),
    db: Session = Depends(get_db),
):
    # Rate limit: max 5 attempts per 10 minutes per phone
    now = datetime.now(timezone.utc)
    window_start, count = _sms_attempt_cache.get(phone, (now, 0))
    if (now - window_start).total_seconds() > 600:
        window_start, count = now, 0
    count += 1
    _sms_attempt_cache[phone] = (window_start, count)
    if count > 5:
        raise HTTPException(status_code=429, detail="Too many OTP attempts. Try again in 10 minutes.")

    user = db.query(models.User).filter(models.User.phone == phone).first()
    if not user:
        raise HTTPException(status_code=404, detail="Phone number not found.")
    if not user.sms_otp_hash:
        raise HTTPException(status_code=400, detail="No OTP pending for this account.")
    now = datetime.now(timezone.utc)
    if user.sms_otp_expires_at and user.sms_otp_expires_at < now:
        raise HTTPException(status_code=400, detail="OTP has expired. Please register again.")
    if _hash_token(otp.strip()) != user.sms_otp_hash:
        raise HTTPException(status_code=400, detail="Invalid OTP.")
    user.verification_status = "approved"
    user.is_active = True
    user.sms_otp_hash = None
    user.sms_otp_expires_at = None
    db.commit()
    return {"detail": "Phone verified successfully. You may now log in."}


# ── Password Reset ────────────────────────────────────────────────────────────

@router.post("/forgot-password")
def forgot_password(payload: schemas.ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    if not user:
        return {"detail": "If that email is registered, an OTP has been sent."}

    # Rate limit: allow at most 1 OTP request per 2 minutes
    recent = db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.user_id == user.id,
        models.PasswordResetToken.used == False,
        models.PasswordResetToken.created_at > datetime.now(timezone.utc) - timedelta(minutes=2),
    ).first()
    if recent:
        raise HTTPException(status_code=429, detail="Please wait before requesting another OTP.")

    db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.user_id == user.id,
        models.PasswordResetToken.used == False,
    ).delete(synchronize_session=False)

    otp = _generate_otp()
    db.add(models.PasswordResetToken(
        user_id=user.id,
        token_hash=_hash_token(otp),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    ))
    db.commit()

    sent = _send_email(
        user.email,
        "Barangay Legal Aid – Password Reset OTP",
        f"Hello {user.first_name},\n\nYour OTP is: {otp}\n\nExpires in 15 minutes.\n\n— Barangay Legal Aid"
    )
    if sent:
        return {"detail": "If that email is registered, an OTP has been sent."}
    return {"detail": "OTP generated. (SMTP not configured – dev mode only.)", "dev_otp": otp}


@router.post("/reset-password")
def reset_password(payload: schemas.ResetPasswordRequest, db: Session = Depends(get_db)):
    if len(payload.new_password) < 8:
        raise HTTPException(status_code=422, detail="New password must be at least 8 characters.")
    token_hash = _hash_token(payload.token.strip())
    now = datetime.now(timezone.utc)
    record = db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.token_hash == token_hash,
        models.PasswordResetToken.used == False,
        models.PasswordResetToken.expires_at > now,
    ).first()
    if not record:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP.")
    record.user.hashed_password = get_password_hash(payload.new_password)
    record.used = True
    db.commit()
    return {"detail": "Password reset successfully. You may now log in."}
