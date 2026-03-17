"""
Mediation service layer.

All business logic for mediation operations lives here.
Routers call these functions and return the results — they contain no
database or business logic themselves.

Transaction guarantee
---------------------
Every multi-step write (schedule, update, delete) is wrapped in a single
db.begin() / db.commit() block.  If any step raises, SQLAlchemy
automatically rolls back the entire unit of work before propagating the
exception upward to the router's error handler.
"""

import os
import uuid
import logging
from datetime import date
from sqlalchemy.orm import Session, joinedload
from sqlalchemy.exc import SQLAlchemyError
from fastapi import HTTPException, status

from app import models, schemas

logger = logging.getLogger(__name__)

_PHOTO_DIR = "uploads/resolution_photos"

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

VALID_RESOLUTION_STATUSES = {"scheduled", "ongoing", "resolved", "failed"}


def _get_case_or_400(db: Session, case_id: int) -> models.Case:
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Complaint not found")
    return case


def _get_mediation_or_400(db: Session, mediation_id: int) -> models.Mediation:
    med = db.query(models.Mediation).filter(models.Mediation.id == mediation_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="Mediation record not found")
    return med


def _validate_schedule_payload(payload: schemas.MediationCreate) -> None:
    """Raise HTTP 400 if required scheduling fields are absent."""
    errors = []
    if not payload.mediation_date:
        errors.append("mediation_date is required")
    if payload.resolution_status not in VALID_RESOLUTION_STATUSES:
        errors.append(
            f"resolution_status must be one of: {', '.join(sorted(VALID_RESOLUTION_STATUSES))}"
        )
    if errors:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Missing required mediation fields", "fields": errors},
        )


def _validate_update_payload(payload: schemas.MediationUpdate) -> None:
    """Raise HTTP 400 if the update contains an invalid resolution_status."""
    if (
        payload.resolution_status is not None
        and payload.resolution_status not in VALID_RESOLUTION_STATUSES
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": "Invalid resolution_status",
                "allowed": sorted(VALID_RESOLUTION_STATUSES),
            },
        )


# ---------------------------------------------------------------------------
# Service functions
# ---------------------------------------------------------------------------

def list_mediations(
    db: Session,
    case_id: int,
    current_user: models.User,
) -> list[models.Mediation]:
    """
    Return all mediation records for a case.
    Users can only see their own cases; admins/staff can see any.
    """
    case = _get_case_or_400(db, case_id)
    if current_user.role == "user" and case.reporter_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    mediations = (
        db.query(models.Mediation)
        .options(joinedload(models.Mediation.mediator))
        .filter(models.Mediation.case_id == case_id)
        .order_by(models.Mediation.mediation_date.asc())
        .all()
    )

    # Back-fill mediator_name in memory for records created before the
    # auto-fill was added. This does NOT write to the DB — it only ensures
    # the API response always carries a human-readable mediator name.
    for m in mediations:
        if not m.mediator_name and m.mediator:
            m.mediator_name = (
                f"{m.mediator.first_name} {m.mediator.last_name}".strip()
                or m.mediator.username
            )

    return mediations


def schedule_mediation(
    db: Session,
    case_id: int,
    payload: schemas.MediationCreate,
    current_user: models.User,
) -> models.Mediation:
    """
    Create a new mediation session and, if the parent case is still pending,
    promote it to 'reviewing'.  A notification is sent to the reporter.

    All writes are committed atomically.  If notification insert fails the
    mediation record is still saved (notification is best-effort).
    """
    _validate_schedule_payload(payload)
    case = _get_case_or_400(db, case_id)

    try:
        data = payload.model_dump(exclude_unset=True)
        # Auto-fill mediator_name from the creating user so it's always visible
        # in the reporter's complaint view even if the admin didn't type a name.
        if not data.get("mediator_name"):
            data["mediator_name"] = (
                f"{current_user.first_name} {current_user.last_name}".strip()
                or current_user.username
            )

        mediation = models.Mediation(
            case_id=case_id,
            mediated_by=current_user.id,
            **data,
        )
        db.add(mediation)

        # Auto-promote case status on first scheduled mediation
        if case.status == "pending":
            case.status = "reviewing"
            logger.info(f"Case {case_id} promoted to 'reviewing' after mediation schedule.")

        db.commit()
        db.refresh(mediation)

    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"schedule_mediation: DB error on case {case_id}: {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while scheduling mediation — please try again.",
        )

    # Notifications are best-effort: failure does not roll back the mediation
    try:
        date_str = str(payload.mediation_date)
        notifications = []
        # Notify the reporter
        if case.reporter_id:
            notifications.append(models.Notification(
                user_id=case.reporter_id,
                title="Mediation Scheduled",
                message=(
                    f"A mediation session for your case '{case.title[:60]}' "
                    f"has been scheduled for {date_str}."
                ),
                notif_type="case_update",
                reference_id=case_id,
            ))
        # Notify registered respondents
        respondents = db.query(models.ComplaintRespondent).filter(
            models.ComplaintRespondent.complaint_id == case_id,
            models.ComplaintRespondent.respondent_id.isnot(None),
        ).all()
        for resp in respondents:
            notifications.append(models.Notification(
                user_id=resp.respondent_id,
                title="Mediation Scheduled",
                message=(
                    f"A mediation session has been scheduled for case "
                    f"'{case.title[:60]}' on {date_str}. Please be present."
                ),
                notif_type="case_update",
                reference_id=case_id,
            ))
        for n in notifications:
            db.add(n)
        if notifications:
            db.commit()
    except SQLAlchemyError as exc:
        db.rollback()
        logger.warning(f"schedule_mediation: notification failed (non-fatal): {exc}")

    return mediation


def update_mediation(
    db: Session,
    mediation_id: int,
    payload: schemas.MediationUpdate,
) -> models.Mediation:
    """
    Update a mediation record.

    Case status sync (atomic):
      • resolution_status → 'resolved'  ⟹  case.status = 'resolved'
      • resolution_status → 'failed'    ⟹  case.status reverts to 'reviewing'

    Both the mediation update and the case status change commit together.
    If either write fails the entire transaction is rolled back.
    """
    _validate_update_payload(payload)
    med = _get_mediation_or_400(db, mediation_id)

    updates = payload.model_dump(exclude_unset=True)
    new_resolution_status = updates.get("resolution_status")

    try:
        # Apply all field updates to the mediation record
        for field, value in updates.items():
            setattr(med, field, value)

        # Sync parent case status inside the same transaction
        if new_resolution_status is not None:
            case = db.query(models.Case).filter(models.Case.id == med.case_id).first()
            if case:
                if new_resolution_status == "resolved":
                    case.status = "resolved"
                    logger.info(
                        f"Case {med.case_id} marked 'resolved' via mediation {mediation_id}."
                    )
                elif new_resolution_status == "failed":
                    # Revert to reviewing so admin can schedule another session
                    if case.status == "resolved":
                        case.status = "reviewing"
                    logger.info(
                        f"Mediation {mediation_id} failed — case {med.case_id} "
                        f"status kept/reverted to '{case.status}'."
                    )

        db.commit()
        db.refresh(med)
        return med

    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"update_mediation: DB error on mediation {mediation_id}: {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while updating mediation — please try again.",
        )


def delete_mediation(db: Session, mediation_id: int) -> dict:
    """
    Delete a mediation record.  Returns a confirmation dict.
    """
    med = _get_mediation_or_400(db, mediation_id)

    try:
        db.delete(med)
        db.commit()
        return {"detail": "Mediation deleted"}
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(f"delete_mediation: DB error on mediation {mediation_id}: {exc}")
        raise HTTPException(
            status_code=503,
            detail="Database error while deleting mediation — please try again.",
        )


def save_resolution_photo(
    db: Session,
    mediation_id: int,
    file_contents: bytes,
    original_filename: str,
) -> models.Mediation:
    """
    Persist an uploaded resolution photo and record its URL on the mediation.

    File write and DB update are kept in the same logical operation:
    if the DB update fails the file is left on disk (orphaned but harmless);
    if the file write fails we never touch the DB.
    """
    med = _get_mediation_or_400(db, mediation_id)

    os.makedirs(_PHOTO_DIR, exist_ok=True)
    ext = os.path.splitext(original_filename or "photo.jpg")[1] or ".jpg"
    fname = f"med_{mediation_id}_{uuid.uuid4().hex[:8]}{ext}"
    fpath = os.path.join(_PHOTO_DIR, fname)

    # Write file first — if this raises we never touch the DB
    with open(fpath, "wb") as f:
        f.write(file_contents)

    try:
        med.resolution_photo_path = f"/uploads/resolution_photos/{fname}"
        db.commit()
        db.refresh(med)
        return med
    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(
            f"save_resolution_photo: DB error on mediation {mediation_id}: {exc}"
        )
        raise HTTPException(
            status_code=503,
            detail="Database error while saving photo — please try again.",
        )
