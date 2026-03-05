from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/cases", tags=["cases"])


# ── Enrichment helper ─────────────────────────────────────────────────────────

def _enrich_respondent(r: models.CaseRespondent) -> schemas.CaseRespondentRead:
    name = r.respondent_name
    if r.is_registered_user and r.respondent_user:
        name = f"{r.respondent_user.first_name} {r.respondent_user.last_name}".strip()
    brgy_name = r.respondent_barangay.name if r.respondent_barangay else None
    return schemas.CaseRespondentRead(
        id=r.id,
        case_id=r.case_id,
        respondent_user_id=r.respondent_user_id,
        respondent_name=r.respondent_name,
        respondent_alias=r.respondent_alias,
        respondent_description=r.respondent_description,
        respondent_barangay_id=r.respondent_barangay_id,
        respondent_barangay_name=brgy_name,
        respondent_address=r.respondent_address,
        respondent_gender=r.respondent_gender,
        is_registered_user=r.is_registered_user,
        name_unknown=r.name_unknown,
        registered_user_name=name if r.is_registered_user else None,
    )


def _enrich(case: models.Case) -> schemas.CaseRead:
    mediation_count = len(case.mediations) if case.mediations else 0
    respondents = [_enrich_respondent(r) for r in (case.respondents or [])]
    return schemas.CaseRead(
        id=case.id,
        title=case.title,
        description=case.description,
        status=case.status or "pending",
        category=case.category,
        urgency=case.urgency or "medium",
        is_cross_barangay=case.is_cross_barangay or False,
        complaint_barangay_id=case.complaint_barangay_id,
        reporter_id=case.reporter_id,
        created_at=case.created_at,
        updated_at=case.updated_at,
        reporter_name=f"{case.reporter.first_name} {case.reporter.last_name}".strip() if case.reporter else None,
        reporter_email=case.reporter.email if case.reporter else None,
        respondents=respondents,
        mediation_count=mediation_count,
    )


# ── Complaint count per respondent ────────────────────────────────────────────

@router.get("/respondent/{user_id}/count")
def get_respondent_complaint_count(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    count = db.query(models.CaseRespondent).filter(
        models.CaseRespondent.respondent_user_id == user_id
    ).count()
    return {"user_id": user_id, "complaint_count": count}


# ── CRUD ──────────────────────────────────────────────────────────────────────

@router.post("/", response_model=schemas.CaseRead)
def create_case(
    case: schemas.CaseCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    new_case = models.Case(
        title=case.title,
        description=case.description,
        status="pending",
        reporter_id=current_user.id,
        category=case.category,
        urgency=case.urgency or "medium",
        is_cross_barangay=case.is_cross_barangay or False,
        complaint_barangay_id=case.complaint_barangay_id,
    )
    db.add(new_case)
    db.flush()   # get new_case.id before inserting respondents

    # Bulk insert respondents in same transaction
    for r in (case.respondents or []):
        db.add(models.CaseRespondent(
            case_id=new_case.id,
            respondent_user_id=r.respondent_user_id,
            respondent_name=r.respondent_name,
            respondent_alias=r.respondent_alias,
            respondent_description=r.respondent_description,
            respondent_barangay_id=r.respondent_barangay_id,
            respondent_address=r.respondent_address,
            respondent_gender=r.respondent_gender,
            is_registered_user=r.is_registered_user,
            name_unknown=r.name_unknown,
        ))

    db.commit()
    db.refresh(new_case)

    # Notify admins/staff in reporter's barangay
    if current_user.barangay_id:
        admins = db.query(models.User).filter(
            models.User.barangay_id == current_user.barangay_id,
            models.User.role.in_(["admin", "superadmin", "staff"]),
            models.User.is_active == True,
        ).all()
        for admin in admins:
            db.add(models.Notification(
                user_id=admin.id,
                title="New Complaint Filed",
                message=(
                    f"{current_user.first_name} {current_user.last_name} "
                    f"filed a complaint: '{new_case.title[:60]}'."
                ),
                notif_type="new_case",
                reference_id=new_case.id,
            ))
        if admins:
            db.commit()

    return _enrich(new_case)


_CASE_EAGER = [
    joinedload(models.Case.reporter),
    joinedload(models.Case.respondents).joinedload(models.CaseRespondent.respondent_user),
    joinedload(models.Case.respondents).joinedload(models.CaseRespondent.respondent_barangay),
    joinedload(models.Case.mediations),
]


@router.get("/", response_model=List[schemas.CaseRead])
def get_cases(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    opts = _CASE_EAGER
    if current_user.role == "superadmin":
        cases = (
            db.query(models.Case)
            .options(*opts)
            .order_by(models.Case.created_at.desc())
            .offset(skip).limit(limit).all()
        )
    elif current_user.role in ("admin", "staff"):
        if not current_user.barangay_id:
            return []
        cases = (
            db.query(models.Case)
            .options(*opts)
            .join(models.User, models.Case.reporter_id == models.User.id)
            .filter(models.User.barangay_id == current_user.barangay_id)
            .order_by(models.Case.created_at.desc())
            .offset(skip).limit(limit).all()
        )
    else:
        cases = (
            db.query(models.Case)
            .options(*opts)
            .filter(models.Case.reporter_id == current_user.id)
            .order_by(models.Case.created_at.desc())
            .offset(skip).limit(limit).all()
        )
    return [_enrich(c) for c in cases]


@router.get("/{case_id}", response_model=schemas.CaseRead)
def get_case(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    if current_user.role == "user":
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
    elif current_user.role in ("admin", "staff"):
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    return _enrich(case)


@router.put("/{case_id}", response_model=schemas.CaseRead)
def update_case(
    case_id: int,
    updated_case: schemas.CaseUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == "user":
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
        updated_case.status = None   # users cannot change status
    elif current_user.role in ("admin", "staff"):
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized")

    # ── Mediation guard: cannot resolve without a mediation record ───────────
    new_status = updated_case.model_dump(exclude_unset=True).get("status")
    if new_status == "resolved":
        med_count = db.query(models.Mediation).filter(
            models.Mediation.case_id == case_id
        ).count()
        if med_count == 0:
            raise HTTPException(
                status_code=400,
                detail="A mediation record is required before resolving a complaint.",
            )

    old_status = case.status
    for key, value in updated_case.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(case, key, value)

    db.commit()
    db.refresh(case)

    # Notify reporter on status change
    if new_status and new_status != old_status and current_user.role in ("admin", "superadmin", "staff"):
        labels = {
            "reviewing": "is now under review 🔍",
            "under_mediation": "is now under mediation ⚖️",
            "resolved": "has been resolved ✓",
            "dismissed": "has been dismissed",
        }
        label = labels.get(new_status, f"status updated to '{new_status}'")
        db.add(models.Notification(
            user_id=case.reporter_id,
            title="Complaint Status Update",
            message=f"Your complaint '{case.title[:60]}' {label}.",
            notif_type="case_update",
            reference_id=case.id,
        ))
        db.commit()

    return _enrich(case)


@router.delete("/{case_id}")
def delete_case(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    if current_user.role == "staff":
        raise HTTPException(status_code=403, detail="Staff cannot delete complaints")
    if current_user.role == "user":
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
    elif current_user.role == "admin":
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    db.delete(case)
    db.commit()
    return {"detail": "Case deleted successfully"}
