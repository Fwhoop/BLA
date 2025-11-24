from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user
import bcrypt
from datetime import datetime
from typing import List

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
    current_user: models.User = Depends(get_current_user)
):
    requested_role = user.role or "user"
    if requested_role in ["admin", "superadmin"]:
        if current_user.role != "superadmin":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only superadmin can create admin or superadmin users"
            )
    
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


@router.get("/", response_model=List[schemas.UserRead])
def read_users(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get all users - filtered by role"""
    if current_user.role == "superadmin":
        return db.query(models.User).all()
    elif current_user.role == "admin":
        if not current_user.barangay_id:
            return []
        return db.query(models.User).filter(
            models.User.barangay_id == current_user.barangay_id
        ).all()
    else:
        return [current_user]


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
