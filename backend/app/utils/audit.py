"""Audit log helper — records security and administrative actions."""
import json
import logging
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def log_action(
    db: Session,
    action_type: str,
    performed_by_id: Optional[int],
    target_user_id: Optional[int],
    metadata: dict = {},
) -> None:
    """
    Insert an audit log entry.
    action_type examples: "login_success", "admin_approved", "admin_rejected",
                          "admin_self_registered", "password_reset", "staff_created"
    """
    try:
        from ..models import AuditLog
        entry = AuditLog(
            action_type=action_type,
            performed_by=performed_by_id,
            target_user_id=target_user_id,
            log_metadata=json.dumps(metadata) if metadata else None,
            created_at=datetime.now(timezone.utc),
        )
        db.add(entry)
        db.commit()
    except Exception as e:
        logger.warning("[AUDIT] Failed to log action '%s': %s", action_type, e)
        db.rollback()
