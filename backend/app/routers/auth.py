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

from .. import models, schemas
from ..db import get_db
from ..core.config import settings
from ..utils.otp import generate_otp, hash_otp, verify_otp
from ..utils.email import send_otp_email, send_password_reset_email
from ..utils.firebase_init import verify_firebase_token
from ..utils.audit import log_action


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

def authenticate_user(db: Session, identifier: str, password: str):
    """Authenticate by email OR phone number."""
    if "@" in identifier:
        user = db.query(models.User).filter(models.User.email == identifier).first()
    else:
        user = db.query(models.User).filter(models.User.phone == identifier).first()
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
    log_action(db, "login_success", user.id, user.id)
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


def _save_upload(upload: UploadFile, subfolder: str = "id_photos") -> Optional[str]:
    """Save an UploadFile to disk and return its relative URL path. Returns None on failure."""
    if not upload or not upload.filename:
        return None
    try:
        upload_dir = os.path.join("uploads", subfolder)
        os.makedirs(upload_dir, exist_ok=True)
        ext = upload.filename.rsplit('.', 1)[-1].lower() if '.' in upload.filename else 'jpg'
        filename = f"{uuid.uuid4().hex}.{ext}"
        contents = upload.file.read()
        with open(os.path.join(upload_dir, filename), "wb") as f:
            f.write(contents)
        return f"/uploads/{subfolder}/{filename}"
    except Exception:
        return None


@router.post("/register", response_model=schemas.UserRead)
def register(
    first_name: str = Form(...),
    last_name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    phone: Optional[str] = Form(None),
    role: Optional[str] = Form("user"),
    # Legacy single address
    address: Optional[str] = Form(None),
    # Philippine address components
    house_number: Optional[str] = Form(None),
    street_name:  Optional[str] = Form(None),
    purok:        Optional[str] = Form(None),
    city:         Optional[str] = Form(None),
    province:     Optional[str] = Form(None),
    zip_code:     Optional[str] = Form(None),
    barangay: Optional[str] = Form(None),
    # Photo uploads
    id_photo:        Optional[UploadFile] = File(None),
    selfie_with_id:  Optional[UploadFile] = File(None),
    profile_photo:   Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    """Public signup endpoint for residents and barangay admin self-registration."""
    if db.query(models.User).filter(models.User.email == email).first():
        raise HTTPException(status_code=400, detail="Email already registered")

    # Sanitize role — only "user" and "admin" are allowed via self-registration
    safe_role = "admin" if role == "admin" else "user"

    base_username = re.sub(r'[^a-z0-9]', '', email.split('@')[0].lower()) or "user"
    username = base_username
    counter = 1
    while db.query(models.User).filter(models.User.username == username).first():
        username = f"{base_username}{counter}"
        counter += 1

    barangay_id = None
    if barangay:
        brgy = db.query(models.Barangay).filter(models.Barangay.name == barangay).first()
        if brgy:
            barangay_id = brgy.id

    # ── Anti-spam: block duplicate pending admin per barangay ─────────────────
    if safe_role == "admin" and barangay_id:
        existing_pending = db.query(models.User).filter(
            models.User.barangay_id == barangay_id,
            models.User.role == "admin",
            models.User.is_active == False,
            models.User.verification_status == "pending",
        ).first()
        if existing_pending:
            raise HTTPException(
                status_code=400,
                detail="A pending admin registration already exists for this barangay. "
                       "Please wait for the superadmin to review it before submitting again.",
            )

    new_user = models.User(
        email=email,
        username=username,
        hashed_password=get_password_hash(password),
        first_name=first_name,
        last_name=last_name,
        phone=phone or "",
        address=address or "",
        house_number=house_number,
        street_name=street_name,
        purok=purok,
        city=city,
        province=province,
        zip_code=zip_code,
        role=safe_role,
        barangay_id=barangay_id,
        is_active=False,
        verification_status="pending",
        id_photo_url=_save_upload(id_photo),
        selfie_with_id_path=_save_upload(selfie_with_id),
        profile_photo_path=_save_upload(profile_photo),
        created_at=datetime.utcnow(),
    )

    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")

    # ── Notify appropriate admins ─────────────────────────────────────────────
    try:
        if safe_role == "admin":
            # Notify all superadmins
            notify_users = db.query(models.User).filter(
                models.User.role == "superadmin",
                models.User.is_active == True,
            ).all()
            notif_title = "New Admin Registration Request"
            notif_msg = f"{first_name} {last_name} has applied to be a barangay admin and is awaiting your approval."
            log_action(db, "admin_self_registered", new_user.id, new_user.id, {"barangay_id": barangay_id})
        else:
            # Notify barangay admins
            notify_users = db.query(models.User).filter(
                models.User.barangay_id == barangay_id,
                models.User.role.in_(["admin", "superadmin"]),
                models.User.is_active == True,
            ).all() if barangay_id else []
            notif_title = "New Resident Registration"
            notif_msg = f"{first_name} {last_name} has registered and is awaiting your approval."

        for u in notify_users:
            db.add(models.Notification(
                user_id=u.id,
                title=notif_title,
                message=notif_msg,
                notif_type="new_user",
                reference_id=new_user.id,
            ))
        if notify_users:
            db.commit()
    except Exception:
        pass

    return new_user


# ── OTP ENDPOINTS ─────────────────────────────────────────────────────────────

@router.post("/send-email-otp")
def send_email_otp(payload: schemas.SendEmailOTPRequest, db: Session = Depends(get_db)):
    """Generate and email a 6-digit OTP for signup verification."""
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    otp = generate_otp()
    user.otp_code = hash_otp(otp)
    user.otp_expiry = datetime.now(timezone.utc) + timedelta(minutes=5)
    user.otp_attempts = 0
    db.commit()

    send_otp_email(user.email, otp)
    return {"message": "OTP sent to your email", "user_id": user.id}


@router.post("/verify-email-otp")
def verify_email_otp(payload: schemas.VerifyEmailOTPRequest, db: Session = Depends(get_db)):
    """Verify the email OTP — sets email_verified=True on success."""
    user = db.query(models.User).filter(models.User.id == payload.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.otp_code or not user.otp_expiry:
        raise HTTPException(status_code=400, detail="No OTP requested. Please request a new one.")
    if (user.otp_attempts or 0) >= 5:
        raise HTTPException(status_code=400, detail="Too many failed attempts. Please request a new OTP.")
    if datetime.now(timezone.utc) > user.otp_expiry.replace(tzinfo=timezone.utc) if user.otp_expiry.tzinfo is None else user.otp_expiry:
        raise HTTPException(status_code=400, detail="OTP has expired. Please request a new one.")
    if not verify_otp(payload.otp, user.otp_code):
        user.otp_attempts = (user.otp_attempts or 0) + 1
        db.commit()
        remaining = 5 - user.otp_attempts
        raise HTTPException(status_code=400, detail=f"Invalid OTP. {remaining} attempt(s) remaining.")

    user.email_verified = True
    user.verification_method = "email"
    user.otp_code = None
    user.otp_expiry = None
    user.otp_attempts = 0
    db.commit()
    return {"message": "Email verified successfully"}


@router.post("/verify-firebase-phone")
def verify_firebase_phone(payload: schemas.VerifyFirebasePhoneRequest, db: Session = Depends(get_db)):
    """Verify a Firebase phone auth ID token — sets mobile_verified=True."""
    user = db.query(models.User).filter(models.User.id == payload.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    try:
        claims = verify_firebase_token(payload.firebase_id_token)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    phone_number = claims.get("phone_number", "")
    user.mobile_verified = True
    user.verification_method = "phone"
    if phone_number:
        user.phone = phone_number
    db.commit()
    return {"message": "Phone verified successfully"}


# ── FORGOT PASSWORD ───────────────────────────────────────────────────────────

@router.post("/forgot-password")
def forgot_password(payload: schemas.ForgotPasswordRequest, db: Session = Depends(get_db)):
    """Initiate password reset via email OTP or Firebase phone OTP."""
    if payload.method == "email":
        user = db.query(models.User).filter(models.User.email == payload.identifier).first()
    else:
        user = db.query(models.User).filter(models.User.phone == payload.identifier).first()

    if not user:
        # Return success to prevent user enumeration
        return {"message": "If the account exists, a reset code has been sent.", "user_id": None}

    if payload.method == "email":
        otp = generate_otp()
        user.otp_code = hash_otp(otp)
        user.otp_expiry = datetime.now(timezone.utc) + timedelta(minutes=5)
        user.otp_attempts = 0
        db.commit()
        send_password_reset_email(user.email, otp)

    # For phone method: client will trigger Firebase OTP directly.
    # We just return the user_id so the client can call reset-password-phone after Firebase verifies.
    return {"message": "If the account exists, a reset code has been sent.", "user_id": user.id}


@router.post("/reset-password")
def reset_password(payload: schemas.ResetPasswordRequest, db: Session = Depends(get_db)):
    """Reset password using email OTP."""
    user = db.query(models.User).filter(models.User.id == payload.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.otp_code or not user.otp_expiry:
        raise HTTPException(status_code=400, detail="No reset code found. Please restart the process.")
    if (user.otp_attempts or 0) >= 5:
        raise HTTPException(status_code=400, detail="Too many failed attempts. Please restart.")
    if datetime.now(timezone.utc) > user.otp_expiry.replace(tzinfo=timezone.utc) if user.otp_expiry.tzinfo is None else user.otp_expiry:
        raise HTTPException(status_code=400, detail="Reset code has expired.")
    if not verify_otp(payload.otp, user.otp_code):
        user.otp_attempts = (user.otp_attempts or 0) + 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid reset code.")

    if len(payload.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters.")

    user.hashed_password = get_password_hash(payload.new_password)
    user.otp_code = None
    user.otp_expiry = None
    user.otp_attempts = 0
    db.commit()
    log_action(db, "password_reset", user.id, user.id, {"method": "email"})
    return {"message": "Password reset successfully"}


@router.post("/reset-password-phone")
def reset_password_phone(payload: schemas.ResetPasswordFirebaseRequest, db: Session = Depends(get_db)):
    """Reset password after Firebase phone OTP verification."""
    user = db.query(models.User).filter(models.User.id == payload.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    try:
        verify_firebase_token(payload.firebase_id_token)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    if len(payload.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters.")

    user.hashed_password = get_password_hash(payload.new_password)
    db.commit()
    log_action(db, "password_reset", user.id, user.id, {"method": "phone"})
    return {"message": "Password reset successfully"}
