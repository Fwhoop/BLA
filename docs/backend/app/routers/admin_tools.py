from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
import bcrypt

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/admin", tags=["admin-tools"])


@router.post("/reset-database")
def reset_database(
    payload: schemas.DatabaseResetRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Superadmin: hard-delete all non-superadmin data (users, barangays, cases,
    requests, notifications, etc.) so the system can be tested from a clean state.

    Requires:
      - confirmation == "CONFIRM" (exact, case-sensitive)
      - password matching the superadmin's current password
    """
    if current_user.role != "superadmin":
        raise HTTPException(status_code=403, detail="Superadmin access required.")

    if payload.confirmation != "CONFIRM":
        raise HTTPException(
            status_code=400,
            detail='Confirmation text must be exactly "CONFIRM".',
        )

    # Verify superadmin password
    try:
        password_ok = bcrypt.checkpw(
            payload.password.encode("utf-8"),
            current_user.hashed_password.encode("utf-8"),
        )
    except Exception:
        password_ok = False

    if not password_ok:
        raise HTTPException(status_code=400, detail="Incorrect password.")

    # Delete in FK-safe order using raw SQL so we bypass ORM cascade quirks
    try:
        with db.bind.begin() as conn:
            conn.execute(text("DELETE FROM notifications"))
            conn.execute(text("DELETE FROM audit_logs"))
            conn.execute(text("DELETE FROM chats"))
            conn.execute(text("DELETE FROM complaint_respondents"))
            conn.execute(text("DELETE FROM mediations"))
            conn.execute(text("DELETE FROM cases"))
            conn.execute(text("DELETE FROM requests"))
            conn.execute(text("DELETE FROM users WHERE role != 'superadmin'"))
            conn.execute(text("DELETE FROM barangays"))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Reset failed: {str(e)}")

    return {"message": "All data has been reset successfully. The system is now clean."}
