from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(tags=["mediations"])


@router.post("/cases/{case_id}/mediations", response_model=schemas.MediationRead)
def create_mediation(
    case_id: int,
    payload: schemas.MediationCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "staff", "superadmin"):
        raise HTTPException(status_code=403, detail="Only staff or admins can create mediation records")

    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Complaint not found")

    mediation = models.Mediation(
        complaint_id=case_id,
        mediated_by=current_user.id,
        **payload.model_dump(exclude_unset=True),
    )
    db.add(mediation)

    # Auto-update case status to "reviewing" when a session is scheduled
    if case.status == "pending":
        case.status = "reviewing"

    db.commit()
    db.refresh(mediation)

    # Notify the reporter
    if case.reporter_id and payload.mediation_date:
        db.add(models.Notification(
            user_id=case.reporter_id,
            title="Mediation Session Scheduled",
            message=(
                f"A mediation session for your case '{case.title[:50]}' "
                f"has been scheduled on {payload.mediation_date}"
                + (f" at {payload.mediation_time}" if payload.mediation_time else "") + "."
            ),
            notif_type="mediation",
            reference_id=case.id,
        ))
        db.commit()

    return mediation


@router.get("/cases/{case_id}/mediations", response_model=List[schemas.MediationRead])
def list_mediations(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Complaint not found")
    if current_user.role == "user" and case.reporter_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    return db.query(models.Mediation).filter(
        models.Mediation.complaint_id == case_id
    ).order_by(models.Mediation.mediation_date.asc()).all()


@router.put("/mediations/{mediation_id}", response_model=schemas.MediationRead)
def update_mediation(
    mediation_id: int,
    payload: schemas.MediationUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "staff", "superadmin"):
        raise HTTPException(status_code=403, detail="Not authorized")

    med = db.query(models.Mediation).filter(models.Mediation.id == mediation_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="Mediation record not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(med, field, value)

    db.commit()
    db.refresh(med)
    return med


@router.delete("/mediations/{mediation_id}")
def delete_mediation(
    mediation_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "staff", "superadmin"):
        raise HTTPException(status_code=403, detail="Not authorized")

    med = db.query(models.Mediation).filter(models.Mediation.id == mediation_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="Mediation record not found")

    db.delete(med)
    db.commit()
    return {"detail": "Mediation deleted"}
