from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/", response_model=List[schemas.NotificationRead])
def get_notifications(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Return the 50 most recent notifications for the current user, newest first."""
    return (
        db.query(models.Notification)
        .filter(models.Notification.user_id == current_user.id)
        .order_by(models.Notification.created_at.desc())
        .limit(50)
        .all()
    )


@router.get("/unread-count", response_model=schemas.UnreadCountRead)
def get_unread_count(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Return the count of unread notifications for the current user (used for badge polling)."""
    count = (
        db.query(models.Notification)
        .filter(
            models.Notification.user_id == current_user.id,
            models.Notification.is_read == False,  # noqa: E712
        )
        .count()
    )
    return {"count": count}


@router.put("/{notification_id}/read", response_model=schemas.NotificationRead)
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Mark a single notification as read."""
    notif = (
        db.query(models.Notification)
        .filter(
            models.Notification.id == notification_id,
            models.Notification.user_id == current_user.id,
        )
        .first()
    )
    if not notif:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")
    notif.is_read = True
    db.commit()
    db.refresh(notif)
    return notif


@router.put("/read-all", response_model=schemas.UnreadCountRead)
def mark_all_read(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Mark all notifications as read for the current user."""
    db.query(models.Notification).filter(
        models.Notification.user_id == current_user.id,
        models.Notification.is_read == False,  # noqa: E712
    ).update({"is_read": True})
    db.commit()
    return {"count": 0}
