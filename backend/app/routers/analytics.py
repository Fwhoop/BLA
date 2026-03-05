from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
from .. import models
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/cases/summary")
def get_case_analytics(
    barangay_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Returns:
    - complaint counts by category (top 5)
    - complaint counts by status
    - top 5 respondents by complaint count
    - complaints per barangay (superadmin only)
    """
    if current_user.role not in ("admin", "superadmin", "staff"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    # Scope: admin sees only their barangay; superadmin can filter or see all
    def _base_case_query():
        q = db.query(models.Case)
        if current_user.role in ("admin", "staff"):
            if not current_user.barangay_id:
                return None
            # filter by cases whose reporter is in this barangay
            q = q.join(models.User, models.Case.reporter_id == models.User.id).filter(
                models.User.barangay_id == current_user.barangay_id
            )
        elif barangay_id:
            q = q.join(models.User, models.Case.reporter_id == models.User.id).filter(
                models.User.barangay_id == barangay_id
            )
        return q

    base = _base_case_query()
    if base is None:
        return {
            "by_category": [],
            "by_status": [],
            "top_respondents": [],
            "by_barangay": [],
        }

    # --- By category ---
    category_rows = (
        db.query(models.Case.category, func.count(models.Case.id).label("count"))
        .join(models.User, models.Case.reporter_id == models.User.id)
        .filter(
            *([models.User.barangay_id == current_user.barangay_id]
              if current_user.role in ("admin", "staff") and current_user.barangay_id
              else [models.User.barangay_id == barangay_id] if barangay_id else [])
        )
        .group_by(models.Case.category)
        .order_by(func.count(models.Case.id).desc())
        .limit(5)
        .all()
    )
    by_category = [
        {"category": row.category or "Uncategorized", "count": row.count}
        for row in category_rows
    ]

    # --- By status ---
    status_rows = (
        db.query(models.Case.status, func.count(models.Case.id).label("count"))
        .join(models.User, models.Case.reporter_id == models.User.id)
        .filter(
            *([models.User.barangay_id == current_user.barangay_id]
              if current_user.role in ("admin", "staff") and current_user.barangay_id
              else [models.User.barangay_id == barangay_id] if barangay_id else [])
        )
        .group_by(models.Case.status)
        .all()
    )
    by_status = [{"status": row.status, "count": row.count} for row in status_rows]

    # --- Top respondents ---
    respondent_filter = []
    if current_user.role in ("admin", "staff") and current_user.barangay_id:
        respondent_filter = [
            models.CaseRespondent.respondent_user_id.isnot(None),
            models.Case.reporter_id == models.User.id,
            models.User.barangay_id == current_user.barangay_id,
        ]
    elif barangay_id:
        respondent_filter = [
            models.CaseRespondent.respondent_user_id.isnot(None),
            models.Case.reporter_id == models.User.id,
            models.User.barangay_id == barangay_id,
        ]
    else:
        respondent_filter = [models.CaseRespondent.respondent_user_id.isnot(None)]

    top_resp_rows = (
        db.query(
            models.CaseRespondent.respondent_user_id,
            models.User.first_name,
            models.User.last_name,
            func.count(models.CaseRespondent.id).label("count"),
        )
        .join(models.Case, models.CaseRespondent.case_id == models.Case.id)
        .join(
            models.User,
            models.CaseRespondent.respondent_user_id == models.User.id,
            isouter=False,
        )
        .filter(*respondent_filter)
        .group_by(
            models.CaseRespondent.respondent_user_id,
            models.User.first_name,
            models.User.last_name,
        )
        .order_by(func.count(models.CaseRespondent.id).desc())
        .limit(5)
        .all()
    )
    top_respondents = [
        {
            "user_id": row.respondent_user_id,
            "name": f"{row.first_name} {row.last_name}".strip(),
            "count": row.count,
        }
        for row in top_resp_rows
    ]

    # --- By barangay (superadmin only) ---
    by_barangay = []
    if current_user.role == "superadmin" and not barangay_id:
        brgy_rows = (
            db.query(
                models.Barangay.id,
                models.Barangay.name,
                func.count(models.Case.id).label("count"),
            )
            .join(models.User, models.Case.reporter_id == models.User.id)
            .join(models.Barangay, models.User.barangay_id == models.Barangay.id)
            .group_by(models.Barangay.id, models.Barangay.name)
            .order_by(func.count(models.Case.id).desc())
            .all()
        )
        by_barangay = [
            {"barangay_id": row.id, "barangay_name": row.name, "count": row.count}
            for row in brgy_rows
        ]

    return {
        "by_category": by_category,
        "by_status": by_status,
        "top_respondents": top_respondents,
        "by_barangay": by_barangay,
    }
