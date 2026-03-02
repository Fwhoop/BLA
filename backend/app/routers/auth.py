from fastapi import APIRouter, Depends, HTTPException, status, Form, UploadFile, File
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from jose import JWTError, jwt
from typing import Optional
import bcrypt
import re
import os
import uuid

from .. import models, schemas
from ..db import get_db


SECRET_KEY = "your_secret_key_here" 
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
    user = authenticate_user(db, form_data.username, form_data.password)
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
