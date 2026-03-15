from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user
from ..utils.audit import log_action
from ..utils.email import send_admin_approved_email, send_admin_rejected_email
import bcrypt
from datetime import datetime, timezone
from typing import List, Optional

router = APIRouter(prefix="/users", tags=["users"])


def hash_password(password: str) -> str:
    password_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')


# ─────────────────────────────────────────────────────────────────────────────
# CREATE USER (admin/superadmin)
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/", response_model=schemas.UserRead)
def create_user(
    user: schemas.UserCreate,
    db: Session = Depends(get_db),
):
    if db.query(models.User).filter(models.User.email == user.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if db.query(models.User).filter(models.User.username == user.username).first():
        raise HTTPException(status_code=400, detail="Username already registered")

    new_user = models.User(
        email=user.email,
        username=user.username,
        hashed_password=hash_password(user.password),
        first_name=user.first_name or "",
        last_name=user.last_name or "",
        role=user.role or "user",
        barangay_id=user.barangay_id,
        is_active=True,
        verification_status="approved",
        created_at=datetime.utcnow(),
    )
    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Database insertion error: {str(e)}")
    return new_user


# ─────────────────────────────────────────────────────────────────────────────
# CREATE STAFF (admin-scoped)
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/staff-member", response_model=schemas.UserRead)
def create_staff_member(
    user: schemas.UserCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "superadmin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Only admins can create staff accounts")
    if current_user.role == "admin":
        if not current_user.barangay_id:
            raise HTTPException(status_code=400, detail="Your account is not assigned to a barangay")
        barangay_id = current_user.barangay_id
    else:
        if not user.barangay_id:
            raise HTTPException(status_code=400, detail="barangay_id is required")
        barangay_id = user.barangay_id

    if db.query(models.User).filter(models.User.email == user.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if db.query(models.User).filter(models.User.username == user.username).first():
        raise HTTPException(status_code=400, detail="Username already registered")

    new_user = models.User(
        email=user.email,
        username=user.username,
        hashed_password=hash_password(user.password),
        first_name=user.first_name or "",
        last_name=user.last_name or "",
        role="staff",
        barangay_id=barangay_id,
        is_active=True,
        verification_status="approved",
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


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY (lightweight counts, no N+1)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/summary", response_model=schemas.UserSummaryRead)
def users_summary(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Returns user counts grouped by status. Used for dashboard cards."""
    q = db.query(models.User).filter(models.User.role == "user")
    if current_user.role == "admin":
        q = q.filter(models.User.barangay_id == current_user.barangay_id)

    all_users = q.all()
    total    = len(all_users)
    pending  = sum(1 for u in all_users if u.verification_status == "pending")
    approved = sum(1 for u in all_users if u.verification_status == "approved")
    rejected = sum(1 for u in all_users if u.verification_status == "rejected")
    active   = sum(1 for u in all_users if u.is_active)
    inactive = sum(1 for u in all_users if not u.is_active)
    return schemas.UserSummaryRead(
        total=total, pending=pending, approved=approved,
        rejected=rejected, active=active, inactive=inactive,
    )


# ─────────────────────────────────────────────────────────────────────────────
# LIST USERS (with search + filter + pagination)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[schemas.UserRead])
def read_users(
    search: Optional[str] = Query(None, description="Search by name, email, or phone"),
    filter_status: Optional[str] = Query(None, alias="status",
        description="pending|approved|rejected|active|inactive|all"),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role == "superadmin":
        q = db.query(models.User)
    elif current_user.role == "admin":
        if not current_user.barangay_id:
            return []
        q = db.query(models.User).filter(
            models.User.barangay_id == current_user.barangay_id
        )
    else:
        return [current_user]

    # Search
    if search:
        term = f"%{search}%"
        q = q.filter(or_(
            models.User.first_name.ilike(term),
            models.User.last_name.ilike(term),
            models.User.email.ilike(term),
            models.User.phone.ilike(term),
        ))

    # Filter by status
    if filter_status and filter_status != "all":
        if filter_status == "active":
            q = q.filter(models.User.is_active == True)
        elif filter_status == "inactive":
            q = q.filter(models.User.is_active == False)
        elif filter_status in ("pending", "approved", "rejected"):
            q = q.filter(models.User.verification_status == filter_status)

    # Pagination
    offset = (page - 1) * limit
    return q.order_by(models.User.created_at.desc()).offset(offset).limit(limit).all()


# ─────────────────────────────────────────────────────────────────────────────
# GET SINGLE USER
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/{user_id}", response_model=schemas.UserRead)
def read_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if current_user.role == "user" and user.id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    if current_user.role == "admin" and user.barangay_id != current_user.barangay_id:
        raise HTTPException(status_code=403, detail="Not authorized to view users from other barangays")
    return user


# ─────────────────────────────────────────────────────────────────────────────
# UPDATE USER
# ─────────────────────────────────────────────────────────────────────────────

@router.put("/{user_id}", response_model=schemas.UserRead)
def update_user(
    user_id: int,
    user_update: schemas.UserUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if user.role == "superadmin" and current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Only superadmin can modify superadmin accounts")
    if user_update.role == "superadmin" and current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Only superadmin can assign superadmin role")
    if user_update.role in ["admin", "superadmin"] and current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Only superadmin can change role to admin or superadmin")
    if current_user.role == "admin":
        if user.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Admins can only update users from their own barangay")
        if user_update.barangay_id and user_update.barangay_id != user.barangay_id:
            raise HTTPException(status_code=403, detail="Admins cannot change user barangay")
    if current_user.role == "user":
        if user.id != current_user.id:
            raise HTTPException(status_code=403, detail="Users can only update their own profile")
        if user_update.role and user_update.role != user.role:
            raise HTTPException(status_code=403, detail="Users cannot change their role")
        if user_update.barangay_id and user_update.barangay_id != user.barangay_id:
            raise HTTPException(status_code=403, detail="Users cannot change their barangay")

    updates = user_update.model_dump(exclude_unset=True)

    # When admin approves (is_active → True), auto-set verification fields
    if updates.get("is_active") is True and not user.is_active:
        updates.setdefault("verification_status", "approved")
        updates.setdefault("approved_by", current_user.id)
        updates["approved_at"] = datetime.utcnow()

    # When admin rejects (is_active stays False but verification_status → rejected)
    if updates.get("verification_status") == "rejected" and updates.get("approved_by") is None:
        updates["approved_by"] = current_user.id
        updates["approved_at"] = datetime.utcnow()

    for attr, value in updates.items():
        if attr == "password" and value:
            setattr(user, "hashed_password", hash_password(value))
        else:
            setattr(user, attr, value)

    db.commit()
    db.refresh(user)
    return user


# ─────────────────────────────────────────────────────────────────────────────
# DELETE USER
# ─────────────────────────────────────────────────────────────────────────────

@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.role == "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin accounts cannot be deleted")
    if current_user.role == "admin" and user.barangay_id != current_user.barangay_id:
        raise HTTPException(status_code=403, detail="Admins can only delete users from their own barangay")

    db.delete(user)
    db.commit()
    return {"detail": "User deleted successfully"}


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN APPROVAL WORKFLOW
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/pending-admins", response_model=List[schemas.PendingAdminRead])
def get_pending_admins(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin: list all pending admin self-registrations."""
    if current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin access required")

    pending = db.query(models.User).filter(
        models.User.role == "admin",
        models.User.verification_status == "pending",
        models.User.is_active == False,
    ).order_by(models.User.created_at.desc()).all()

    result = []
    for u in pending:
        barangay_name = u.barangay.name if u.barangay else None
        result.append(schemas.PendingAdminRead(
            id=u.id,
            first_name=u.first_name,
            last_name=u.last_name,
            email=u.email,
            phone=u.phone,
            barangay_id=u.barangay_id,
            barangay_name=barangay_name,
            verification_status=u.verification_status,
            created_at=u.created_at,
        ))
    return result


@router.post("/{user_id}/approve-admin", response_model=schemas.UserRead)
def approve_admin(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin: approve a pending barangay admin registration."""
    if current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin access required")

    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.role != "admin":
        raise HTTPException(status_code=400, detail="Target user is not a barangay admin")

    user.is_active = True
    user.verification_status = "approved"
    user.approved_by = current_user.id
    user.approved_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(user)

    # Notify the approved admin
    try:
        db.add(models.Notification(
            user_id=user.id,
            title="Admin Account Approved",
            message=f"Your barangay admin account has been approved by {current_user.first_name} {current_user.last_name}. You can now log in.",
            notif_type="account_approved",
            reference_id=user.id,
        ))
        db.commit()
    except Exception:
        pass

    send_admin_approved_email(user.email, f"{user.first_name} {user.last_name}")
    log_action(db, "admin_approved", current_user.id, user.id,
               {"approved_by_name": f"{current_user.first_name} {current_user.last_name}"})
    return user


@router.post("/{user_id}/reject-admin", response_model=schemas.UserRead)
def reject_admin(
    user_id: int,
    payload: schemas.AdminApprovalAction,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin: reject a pending barangay admin registration."""
    if current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin access required")

    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.verification_status = "rejected"
    user.rejected_by = current_user.id
    user.rejected_at = datetime.now(timezone.utc)
    user.rejection_reason = payload.reason
    db.commit()
    db.refresh(user)

    # Notify the rejected admin
    try:
        msg = "Your barangay admin registration has been rejected."
        if payload.reason:
            msg += f" Reason: {payload.reason}"
        db.add(models.Notification(
            user_id=user.id,
            title="Admin Registration Update",
            message=msg,
            notif_type="account_rejected",
            reference_id=user.id,
        ))
        db.commit()
    except Exception:
        pass

    send_admin_rejected_email(user.email, f"{user.first_name} {user.last_name}", payload.reason or "")
    log_action(db, "admin_rejected", current_user.id, user.id,
               {"reason": payload.reason, "rejected_by_name": f"{current_user.first_name} {current_user.last_name}"})
    return user


# ─────────────────────────────────────────────────────────────────────────────
# AUDIT LOGS
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/audit-logs", response_model=List[schemas.AuditLogRead])
def get_audit_logs(
    action_type: Optional[str] = Query(None),
    target_user_id: Optional[int] = Query(None),
    limit: int = Query(50, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin: retrieve audit log entries."""
    if current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin access required")

    query = db.query(models.AuditLog)
    if action_type:
        query = query.filter(models.AuditLog.action_type == action_type)
    if target_user_id:
        query = query.filter(models.AuditLog.target_user_id == target_user_id)
    return query.order_by(models.AuditLog.created_at.desc()).limit(limit).all()
