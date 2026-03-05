from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/mediations", tags=["mediations"])


def _enrich(m: models.Mediation) -> schemas.MediationRead:
    mediator_name = None
    if m.mediator:
        mediator_name = f"{m.mediator.first_name} {m.mediator.last_name}".strip()
    return schemas.MediationRead(
        id=m.id,
        case_id=m.case_id,
        mediated_by=m.mediated_by,
        mediator_name=mediator_name,
        mediation_date=m.mediation_date,
        mediation_time=m.mediation_time,
        location=m.location,
        summary_notes=m.summary_notes,
        resolution_status=m.resolution_status,
        next_hearing_date=m.next_hearing_date,
        agreement_document_path=m.agreement_document_path,
        created_at=m.created_at,
    )


@router.post("/", response_model=schemas.MediationRead)
def create_mediation(
    payload: schemas.MediationCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "superadmin", "staff"):
        raise HTTPException(status_code=403, detail="Only admin/staff can record mediations.")

    case = db.query(models.Case).filter(models.Case.id == payload.case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found.")

    # Admin scope check
    if current_user.role == "admin":
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized for this case.")

    valid_statuses = {"ongoing", "resolved", "failed", "adjourned"}
    if payload.resolution_status not in valid_statuses:
        raise HTTPException(status_code=422, detail=f"resolution_status must be one of {valid_statuses}")

    m = models.Mediation(
        case_id=payload.case_id,
        mediated_by=current_user.id,
        mediation_date=payload.mediation_date,
        mediation_time=payload.mediation_time,
        location=payload.location,
        summary_notes=payload.summary_notes,
        resolution_status=payload.resolution_status,
        next_hearing_date=payload.next_hearing_date,
        agreement_document_path=payload.agreement_document_path,
    )
    db.add(m)

    # Auto-set case to under_mediation if not already resolved/dismissed
    if case.status not in ("resolved", "dismissed"):
        case.status = "under_mediation"

    db.commit()
    db.refresh(m)
    return _enrich(m)


@router.get("/", response_model=List[schemas.MediationRead])
def list_mediations(
    case_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "superadmin", "staff"):
        raise HTTPException(status_code=403, detail="Not authorized.")
    q = db.query(models.Mediation)
    if case_id:
        q = q.filter(models.Mediation.case_id == case_id)
    return [_enrich(m) for m in q.order_by(models.Mediation.created_at.desc()).all()]


@router.put("/{mediation_id}", response_model=schemas.MediationRead)
def update_mediation(
    mediation_id: int,
    payload: schemas.MediationUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "superadmin", "staff"):
        raise HTTPException(status_code=403, detail="Not authorized.")
    m = db.query(models.Mediation).filter(models.Mediation.id == mediation_id).first()
    if not m:
        raise HTTPException(status_code=404, detail="Mediation record not found.")
    for key, value in payload.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(m, key, value)
    db.commit()
    db.refresh(m)
    return _enrich(m)
