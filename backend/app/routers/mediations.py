from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError
from typing import List
import os, uuid, logging

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(tags=["mediations"])

_PHOTO_DIR = "uploads/resolution_photos"


def _require_admin(current_user: models.User) -> None:
    if current_user.role not in ("admin", "staff", "superadmin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only staff or admins can manage mediation records",
        )


def _get_case_or_404(db: Session, case_id: int) -> models.Case:
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Complaint not found")
    return case


def _get_mediation_or_404(db: Session, mediation_id: int) -> models.Mediation:
    med = db.query(models.Mediation).filter(models.Mediation.id == mediation_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="Mediation record not found")
    return med


# ── GET /cases/{case_id}/mediations ──────────────────────────────────────────
@router.get("/cases/{case_id}/mediations", response_model=List[schemas.MediationRead])
def list_mediations(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    try:
        case = _get_case_or_404(db, case_id)
        if current_user.role == "user" and case.reporter_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")

        return (
            db.query(models.Mediation)
            .filter(models.Mediation.case_id == case_id)
            .order_by(models.Mediation.mediation_date.asc())
            .all()
        )
    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        logger.error(f"list_mediations DB error (case {case_id}): {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while fetching mediations — please try again.",
        )


# ── POST /cases/{case_id}/mediations ─────────────────────────────────────────
@router.post("/cases/{case_id}/mediations", response_model=schemas.MediationRead)
def create_mediation(
    case_id: int,
    payload: schemas.MediationCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)

    try:
        case = _get_case_or_404(db, case_id)

        mediation = models.Mediation(
            case_id=case_id,
            mediated_by=current_user.id,
            **payload.model_dump(exclude_unset=True),
        )
        db.add(mediation)

        # Auto-promote case to "reviewing" on first mediation schedule
        if case.status == "pending":
            case.status = "reviewing"

        db.commit()
        db.refresh(mediation)

        # Notify the reporter
        if case.reporter_id:
            date_str = (
                str(payload.mediation_date)
                if payload.mediation_date
                else "a date to be confirmed"
            )
            db.add(models.Notification(
                user_id=case.reporter_id,
                title="Mediation Scheduled",
                message=(
                    f"A mediation session for your case '{case.title[:60]}' "
                    f"has been scheduled for {date_str}."
                ),
                notif_type="case_update",
                reference_id=case_id,
            ))
            db.commit()

        return mediation

    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"create_mediation DB error (case {case_id}): {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while creating mediation — please try again.",
        )


# ── PUT /mediations/{mediation_id} ───────────────────────────────────────────
@router.put("/mediations/{mediation_id}", response_model=schemas.MediationRead)
def update_mediation(
    mediation_id: int,
    payload: schemas.MediationUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)

    try:
        med = _get_mediation_or_404(db, mediation_id)
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(med, field, value)
        db.commit()
        db.refresh(med)
        return med
    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"update_mediation DB error ({mediation_id}): {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while updating mediation — please try again.",
        )


# ── DELETE /mediations/{mediation_id} ────────────────────────────────────────
@router.delete("/mediations/{mediation_id}")
def delete_mediation(
    mediation_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)

    try:
        med = _get_mediation_or_404(db, mediation_id)
        db.delete(med)
        db.commit()
        return {"detail": "Mediation deleted"}
    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"delete_mediation DB error ({mediation_id}): {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while deleting mediation — please try again.",
        )


# ── POST /mediations/{mediation_id}/upload-resolution-photo ──────────────────
@router.post(
    "/mediations/{mediation_id}/upload-resolution-photo",
    response_model=schemas.MediationRead,
)
async def upload_resolution_photo(
    mediation_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)

    try:
        med = _get_mediation_or_404(db, mediation_id)

        os.makedirs(_PHOTO_DIR, exist_ok=True)
        ext = os.path.splitext(file.filename or "photo.jpg")[1] or ".jpg"
        fname = f"med_{mediation_id}_{uuid.uuid4().hex[:8]}{ext}"
        fpath = os.path.join(_PHOTO_DIR, fname)

        contents = await file.read()
        with open(fpath, "wb") as f:
            f.write(contents)

        med.resolution_photo_path = f"/uploads/resolution_photos/{fname}"
        db.commit()
        db.refresh(med)
        return med

    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"upload_resolution_photo DB error ({mediation_id}): {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while saving photo — please try again.",
        )
