from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user
import bcrypt
from datetime import datetime
from typing import List, Optional

router = APIRouter(prefix="/users", tags=["users"])


def hash_password(password: str) -> str:
    """Hash password using bcrypt directly (compatible with Python 3.13)"""
    password_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')


@router.post("/", response_model=schemas.UserRead)
def create_user(
    user: schemas.UserCreate,
    db: Session = Depends(get_db),
    # TEMPORARY: auth disabled for testing – re-enable after creating accounts (see comment below)
    # current_user: models.User = Depends(get_current_user)
):
    requested_role = user.role or "user"
    # When auth is re-enabled, uncomment the dependency above and this check:
    # if requested_role in ["admin", "superadmin"]:
    #     if current_user.role != "superadmin":
    #         raise HTTPException(
    #             status_code=status.HTTP_403_FORBIDDEN,
    #             detail="Only superadmin can create admin or superadmin users"
    #         )

    if db.query(models.User).filter(models.User.email == user.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if db.query(models.User).filter(models.User.username == user.username).first():
        raise HTTPException(status_code=400, detail="Username already registered")

    hashed_pw = hash_password(user.password)

    new_user = models.User(
        email=user.email,
        username=user.username,
        hashed_password=hashed_pw,
        first_name=user.first_name or "",
        last_name=user.last_name or "",
        role=requested_role,
        barangay_id=user.barangay_id,
        is_active=True,
        created_at=datetime.utcnow()
    )

    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Database insertion error: {str(e)}")

    return new_user


@router.post("/staff-member", response_model=schemas.UserRead)
def create_staff_member(
    user: schemas.UserCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Admin creates a staff account for their own barangay. Superadmin can specify any barangay."""
    if current_user.role not in ("admin", "superadmin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins can create staff accounts",
        )

    if current_user.role == "admin":
        if not current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your account is not assigned to a barangay",
            )
        barangay_id = current_user.barangay_id
    else:  # superadmin
        if not user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="barangay_id is required",
            )
        barangay_id = user.barangay_id

    if db.query(models.User).filter(models.User.email == user.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if db.query(models.User).filter(models.User.username == user.username).first():
        raise HTTPException(status_code=400, detail="Username already registered")

    hashed_pw = hash_password(user.password)
    new_user = models.User(
        email=user.email,
        username=user.username,
        hashed_password=hashed_pw,
        first_name=user.first_name or "",
        last_name=user.last_name or "",
        role="staff",
        barangay_id=barangay_id,
        is_active=True,
        created_at=datetime.utcnow(),
    )

    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

    return new_user


@router.get("/search", response_model=List[schemas.UserRead])
def search_users(
    name: Optional[str] = Query(None),
    barangay_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Search users by name for respondent lookup in complaint form."""
    q = db.query(models.User).filter(models.User.role == "user")
    if name:
        term = f"%{name}%"
        q = q.filter(
            or_(
                models.User.first_name.ilike(term),
                models.User.last_name.ilike(term),
            )
        )
    if barangay_id:
        q = q.filter(models.User.barangay_id == barangay_id)
    return q.limit(20).all()


@router.get("/", response_model=List[schemas.UserRead])
def read_users(
    status: Optional[str] = Query(None),          # all|pending_verification|approved|rejected|active|inactive
    search: Optional[str] = Query(None),           # name, email, phone
    barangay_id: Optional[int] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Get users with optional filter and search — default returns all visible users."""
    q = db.query(models.User)

    # Role-scoped base filter
    if current_user.role == "admin":
        if not current_user.barangay_id:
            return []
        q = q.filter(models.User.barangay_id == current_user.barangay_id)
    elif current_user.role not in ("superadmin",):
        return [current_user]

    # Optional barangay filter (superadmin only)
    if barangay_id and current_user.role == "superadmin":
        q = q.filter(models.User.barangay_id == barangay_id)

    # Status filter
    if status and status != "all":
        if status == "active":
            q = q.filter(models.User.is_active == True)
        elif status == "inactive":
            q = q.filter(models.User.is_active == False)
        else:
            # pending_verification | approved | rejected
            q = q.filter(models.User.verification_status == status)

    # Search filter
    if search:
        term = f"%{search}%"
        q = q.filter(
            or_(
                models.User.first_name.ilike(term),
                models.User.last_name.ilike(term),
                models.User.email.ilike(term),
                models.User.phone.ilike(term),
            )
        )

    return q.order_by(models.User.created_at.desc()).offset(skip).limit(limit).all()


@router.get("/{user_id}", response_model=schemas.UserRead)
def read_user(
    user_id: int, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if current_user.role == "user":
        if user.id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to view this user"
            )
    elif current_user.role == "admin":
        if user.barangay_id != current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to view users from other barangays"
            )
    
    return user


@router.put("/{user_id}", response_model=schemas.UserRead)
def update_user(
    user_id: int, 
    user_update: schemas.UserUpdate, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Prevent modification of superadmin accounts by non-superadmins
    if user.role == "superadmin" and current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can modify superadmin accounts"
        )
    
    # Prevent changing role to superadmin
    if user_update.role == "superadmin" and current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can change user role to superadmin"
        )

    # Check if trying to change role to admin or superadmin
    if user_update.role and user_update.role in ["admin", "superadmin"]:
        # Only superadmins can change roles to admin or superadmin
        if current_user.role != "superadmin":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only superadmin can change user role to admin or superadmin"
            )
    
    # Admins can only update users from their barangay
    if current_user.role == "admin":
        if user.barangay_id != current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admins can only update users from their own barangay"
            )
        # Admins cannot change barangay_id
        if user_update.barangay_id and user_update.barangay_id != user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admins cannot change user barangay"
            )
    
    # Users can only update their own profile
    if current_user.role == "user":
        if user.id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Users can only update their own profile"
            )
        # Users cannot change their role or barangay_id
        if user_update.role and user_update.role != user.role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Users cannot change their role"
            )
        if user_update.barangay_id and user_update.barangay_id != user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Users cannot change their barangay"
            )

    for attr, value in user_update.dict(exclude_unset=True).items():
        if attr == "password" and value:
            setattr(user, "hashed_password", hash_password(value))
        else:
            setattr(user, attr, value)

    db.commit()
    db.refresh(user)
    return user


@router.delete("/{user_id}")
def delete_user(
    user_id: int, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Prevent deletion of superadmin accounts
    if user.role == "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Superadmin accounts cannot be deleted"
        )
    
    # Admins can only delete users from their barangay
    if current_user.role == "admin":
        if user.barangay_id != current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admins can only delete users from their own barangay"
            )

    db.delete(user)
    db.commit()
    return {"detail": "User deleted successfully"}
