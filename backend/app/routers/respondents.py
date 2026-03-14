from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/cases", tags=["respondents"])


@router.post("/{case_id}/respondents", response_model=schemas.ComplaintRespondentRead)
def add_respondent(
    case_id: int,
    respondent: schemas.ComplaintRespondentCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Complaint not found")

    # Only the reporter or admin/staff can add respondents
    if current_user.role == "user" and case.reporter_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    # If respondent is a registered user, populate name and barangay from their profile
    respondent_name = respondent.respondent_name
    respondent_barangay_id = respondent.respondent_barangay_id
    if respondent.is_registered_user and respondent.respondent_id:
        reg_user = db.query(models.User).filter(
            models.User.id == respondent.respondent_id
        ).first()
        if reg_user:
            respondent_name = f"{reg_user.first_name} {reg_user.last_name}".strip()
            respondent_barangay_id = respondent_barangay_id or reg_user.barangay_id

    new_respondent = models.ComplaintRespondent(
        complaint_id=case_id,
        respondent_id=respondent.respondent_id if respondent.is_registered_user else None,
        respondent_barangay_id=respondent_barangay_id,
        respondent_name=respondent_name,
        respondent_address=respondent.respondent_address,
        is_registered_user=respondent.is_registered_user,
        unknown_name=respondent.unknown_name,
    )
    db.add(new_respondent)

    # Mark case as cross-barangay if respondent belongs to a different barangay
    if (respondent_barangay_id and case.reporter and
            respondent_barangay_id != case.reporter.barangay_id):
        case.is_cross_barangay = True

        # Notify admins of respondent's barangay
        try:
            resp_admins = db.query(models.User).filter(
                models.User.barangay_id == respondent_barangay_id,
                models.User.role.in_(["admin", "superadmin"]),
                models.User.is_active == True,
            ).all()
            for admin in resp_admins:
                db.add(models.Notification(
                    user_id=admin.id,
                    title="Cross-Barangay Complaint",
                    message=(
                        f"A complaint has been filed involving a resident of your barangay. "
                        f"Respondent: {respondent_name or 'Unknown'}."
                    ),
                    notif_type="new_case",
                    reference_id=case_id,
                ))
        except Exception:
            pass

    db.commit()
    db.refresh(new_respondent)
    return new_respondent


@router.get("/{case_id}/respondents", response_model=List[schemas.ComplaintRespondentRead])
def get_respondents(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Complaint not found")
    if current_user.role == "user" and case.reporter_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    return db.query(models.ComplaintRespondent).filter(
        models.ComplaintRespondent.complaint_id == case_id
    ).all()


@router.delete("/{case_id}/respondents/{respondent_id}")
def delete_respondent(
    case_id: int,
    respondent_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    record = db.query(models.ComplaintRespondent).filter(
        models.ComplaintRespondent.id == respondent_id,
        models.ComplaintRespondent.complaint_id == case_id,
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="Respondent not found")
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if current_user.role == "user" and case and case.reporter_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    db.delete(record)
    db.commit()
    return {"detail": "Respondent removed"}
