from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/summary", response_model=schemas.AnalyticsSummary)
def get_summary(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Full analytics summary. Superadmin sees all; admin sees their barangay."""
    is_super = current_user.role == "superadmin"
    brgy_id  = current_user.barangay_id if not is_super else None

    # ── Base queries ───────────────────────────────────────────────────────
    case_q    = db.query(models.Case)
    request_q = db.query(models.Request)
    user_q    = db.query(models.User).filter(models.User.role == "user")

    if not is_super and brgy_id:
        # Admin: filter by reporter's barangay
        case_q    = case_q.join(models.User, models.Case.reporter_id == models.User.id)\
                          .filter(models.User.barangay_id == brgy_id)
        request_q = request_q.filter(models.Request.barangay_id == brgy_id)
        user_q    = user_q.filter(models.User.barangay_id == brgy_id)

    total_complaints = case_q.count()
    total_requests   = request_q.count()
    total_users      = user_q.count()
    total_barangays  = db.query(models.Barangay).count()
    pending_complaints  = case_q.filter(models.Case.status == "pending").count()
    resolved_complaints = case_q.filter(models.Case.status == "resolved").count()

    # ── Complaints by type ─────────────────────────────────────────────────
    type_rows = (
        db.query(models.Case.category, func.count(models.Case.id).label("cnt"))
        .group_by(models.Case.category)
        .order_by(func.count(models.Case.id).desc())
        .all()
    ) if is_super else (
        db.query(models.Case.category, func.count(models.Case.id).label("cnt"))
        .join(models.User, models.Case.reporter_id == models.User.id)
        .filter(models.User.barangay_id == brgy_id)
        .group_by(models.Case.category)
        .order_by(func.count(models.Case.id).desc())
        .all()
    )
    complaints_by_type = [
        schemas.ComplaintTypeStat(category=r.category or "Uncategorized", count=r.cnt)
        for r in type_rows
    ]

    # ── Top respondents ────────────────────────────────────────────────────
    resp_rows = (
        db.query(
            models.ComplaintRespondent.respondent_name,
            models.Barangay.name.label("brgy"),
            func.count(models.ComplaintRespondent.id).label("cnt"),
        )
        .outerjoin(models.Barangay,
                   models.ComplaintRespondent.respondent_barangay_id == models.Barangay.id)
        .group_by(models.ComplaintRespondent.respondent_name, models.Barangay.name)
        .order_by(func.count(models.ComplaintRespondent.id).desc())
        .limit(10)
        .all()
    )
    top_respondents = [
        schemas.RespondentStat(
            respondent_name=r.respondent_name or "Unknown",
            barangay=r.brgy,
            complaint_count=r.cnt,
        )
        for r in resp_rows
    ]

    # ── Complaints per barangay ────────────────────────────────────────────
    brgy_rows = (
        db.query(
            models.Barangay.name,
            func.count(models.Case.id).label("complaint_cnt"),
        )
        .outerjoin(models.User, models.User.barangay_id == models.Barangay.id)
        .outerjoin(models.Case, models.Case.reporter_id == models.User.id)
        .group_by(models.Barangay.id, models.Barangay.name)
        .order_by(func.count(models.Case.id).desc())
        .all()
    )
    # Request counts per barangay
    req_brgy_rows = (
        db.query(models.Request.barangay_id, func.count(models.Request.id).label("req_cnt"))
        .group_by(models.Request.barangay_id)
        .all()
    )
    req_map = {r.barangay_id: r.req_cnt for r in req_brgy_rows}
    brgy_obj = db.query(models.Barangay).all()
    brgy_id_to_name = {b.id: b.name for b in brgy_obj}

    complaints_by_barangay = [
        schemas.BarangayStat(
            barangay=r.name,
            complaint_count=r.complaint_cnt,
            request_count=req_map.get(
                next((k for k, v in brgy_id_to_name.items() if v == r.name), None), 0
            ),
        )
        for r in brgy_rows
    ]

    return schemas.AnalyticsSummary(
        total_complaints=total_complaints,
        total_requests=total_requests,
        total_users=total_users,
        total_barangays=total_barangays,
        pending_complaints=pending_complaints,
        resolved_complaints=resolved_complaints,
        complaints_by_type=complaints_by_type,
        top_respondents=top_respondents,
        complaints_by_barangay=complaints_by_barangay,
    )
