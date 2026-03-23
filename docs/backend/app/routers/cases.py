import os, uuid
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_
from typing import List
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/cases", tags=["cases"])

_ATTACHMENT_DIR = "uploads/attachments"


def _enrich(case: models.Case) -> dict:
    """Add reporter_name, reporter_email, category, urgency, is_cross_barangay to a case dict."""
    d = {
        "id": case.id,
        "title": case.title,
        "description": case.description,
        "category": getattr(case, "category", None),
        "urgency": getattr(case, "urgency", "medium"),
        "status": case.status if case.status else "pending",
        "is_cross_barangay": bool(getattr(case, "is_cross_barangay", False)),
        "target_barangay_id": getattr(case, "target_barangay_id", None),
        "target_barangay_name": None,
        "attachment_path": getattr(case, "attachment_path", None),
        "reporter_id": case.reporter_id,
        "created_at": case.created_at,
        "updated_at": case.updated_at,
        "reporter_name": None,
        "reporter_email": None,
        "reporter_barangay": None,
    }
    if case.reporter:
        d["reporter_name"] = f"{case.reporter.first_name} {case.reporter.last_name}".strip()
        d["reporter_email"] = case.reporter.email
        if case.reporter.barangay:
            d["reporter_barangay"] = case.reporter.barangay.name
    target_brgy = getattr(case, "target_barangay", None)
    if target_brgy:
        d["target_barangay_name"] = target_brgy.name
    return d


@router.post("/", response_model=schemas.CaseRead)
def create_case(
    case: schemas.CaseCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    is_cross = case.target_barangay_id is not None and case.target_barangay_id != current_user.barangay_id
    new_case = models.Case(
        title=case.title,
        description=case.description,
        category=case.category,
        urgency=case.urgency or "medium",
        status="pending",
        reporter_id=current_user.id,
        target_barangay_id=case.target_barangay_id,
        is_cross_barangay=is_cross,
    )
    db.add(new_case)
    db.commit()
    db.refresh(new_case)

    # Notify admins in the reporter's own barangay
    notified_barangay_ids = set()
    if current_user.barangay_id:
        notified_barangay_ids.add(current_user.barangay_id)
        admins = db.query(models.User).filter(
            models.User.barangay_id == current_user.barangay_id,
            models.User.role.in_(["admin", "superadmin"]),
            models.User.is_active == True,
        ).all()
        for admin in admins:
            db.add(models.Notification(
                user_id=admin.id,
                title="New Case Filed",
                message=(
                    f"{current_user.first_name} {current_user.last_name} "
                    f"filed a case: '{new_case.title[:60]}'."
                ),
                notif_type="new_case",
                reference_id=new_case.id,
            ))
        if admins:
            db.commit()

    # If cross-barangay suggestion, also notify target barangay admins
    if is_cross and case.target_barangay_id and case.target_barangay_id not in notified_barangay_ids:
        target_admins = db.query(models.User).filter(
            models.User.barangay_id == case.target_barangay_id,
            models.User.role.in_(["admin", "superadmin"]),
            models.User.is_active == True,
        ).all()
        for admin in target_admins:
            db.add(models.Notification(
                user_id=admin.id,
                title="Cross-Barangay Suggestion Received",
                message=(
                    f"A suggestion was submitted by a resident of another barangay: "
                    f"'{new_case.title[:60]}'."
                ),
                notif_type="new_case",
                reference_id=new_case.id,
            ))
        if target_admins:
            db.commit()

    return _enrich(new_case)


@router.get("/", response_model=List[schemas.CaseRead])
def get_cases(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    _eager = joinedload(models.Case.reporter).joinedload(models.User.barangay)
    if current_user.role == "superadmin":
        cases = db.query(models.Case).options(_eager).order_by(models.Case.created_at.desc()).all()
    elif current_user.role == "admin":
        if not current_user.barangay_id:
            return []
        cases = (
            db.query(models.Case)
            .options(_eager)
            .join(models.User, models.Case.reporter_id == models.User.id)
            .outerjoin(
                models.ComplaintRespondent,
                models.ComplaintRespondent.complaint_id == models.Case.id,
            )
            .filter(or_(
                models.User.barangay_id == current_user.barangay_id,
                models.ComplaintRespondent.respondent_barangay_id == current_user.barangay_id,
                models.Case.target_barangay_id == current_user.barangay_id,
            ))
            .distinct()
            .order_by(models.Case.created_at.desc())
            .all()
        )
    else:
        cases = (
            db.query(models.Case)
            .options(_eager)
            .filter(models.Case.reporter_id == current_user.id)
            .order_by(models.Case.created_at.desc())
            .all()
        )
    return [_enrich(c) for c in cases]


@router.get("/{case_id}", response_model=schemas.CaseRead)
def get_case(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    _eager = joinedload(models.Case.reporter).joinedload(models.User.barangay)
    case = db.query(models.Case).options(_eager).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == "user":
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to view this case")
    elif current_user.role == "admin":
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        reporter_match = reporter and reporter.barangay_id == current_user.barangay_id
        respondent_match = db.query(models.ComplaintRespondent).filter(
            models.ComplaintRespondent.complaint_id == case_id,
            models.ComplaintRespondent.respondent_barangay_id == current_user.barangay_id,
        ).first() is not None
        if not reporter_match and not respondent_match:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to view cases from other barangays")

    return _enrich(case)


@router.put("/{case_id}", response_model=schemas.CaseRead)
def update_case(
    case_id: int,
    updated_case: schemas.CaseUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    _eager = joinedload(models.Case.reporter).joinedload(models.User.barangay)
    case = db.query(models.Case).options(_eager).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == "user":
        # Users can only edit their own cases (not status)
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to update this case")
        # Users cannot change status
        updated_case.status = None
    elif current_user.role == "admin":
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        reporter_match = reporter and reporter.barangay_id == current_user.barangay_id
        respondent_match = db.query(models.ComplaintRespondent).filter(
            models.ComplaintRespondent.complaint_id == case_id,
            models.ComplaintRespondent.respondent_barangay_id == current_user.barangay_id,
        ).first() is not None
        if not reporter_match and not respondent_match:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to update cases from other barangays")

    old_status = case.status
    updates = updated_case.model_dump(exclude_unset=True)

    # Enforce: cannot mark Resolved without at least one mediation record
    if updates.get("status") == "resolved":
        mediation_count = db.query(models.Mediation).filter(
            models.Mediation.case_id == case_id
        ).count()
        if mediation_count == 0:
            raise HTTPException(
                status_code=400,
                detail="Cannot mark complaint as resolved without a mediation record. Please add a mediation session first.",
            )

    for key, value in updates.items():
        if value is not None:
            setattr(case, key, value)

    db.commit()
    db.refresh(case)

    # Notify the reporter when admin changes case status
    new_status = updated_case.model_dump(exclude_unset=True).get("status")
    if (
        new_status is not None
        and new_status != old_status
        and current_user.role in ("admin", "superadmin")
        and case.reporter_id
    ):
        labels = {
            "reviewing": "is now under review 🔍",
            "resolved": "has been resolved ✓",
            "dismissed": "has been dismissed",
        }
        label = labels.get(new_status, f"status updated to '{new_status}'")
        db.add(models.Notification(
            user_id=case.reporter_id,
            title="Case Status Update",
            message=f"Your case '{case.title[:60]}' {label}.",
            notif_type="case_update",
            reference_id=case.id,
        ))
        db.commit()

    return _enrich(case)


@router.delete("/{case_id}")
def delete_case(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == "user":
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to delete this case")
    elif current_user.role == "admin":
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to delete cases from other barangays")

    db.delete(case)
    db.commit()
    return {"detail": "Case deleted successfully"}


@router.post("/{case_id}/upload-attachment", response_model=schemas.CaseRead)
async def upload_attachment(
    case_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Upload a photo/attachment for a suggestion (reporter only)."""
    _eager = joinedload(models.Case.reporter).joinedload(models.User.barangay)
    case = db.query(models.Case).options(_eager).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    if current_user.role == "user" and case.reporter_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    os.makedirs(_ATTACHMENT_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "attachment.jpg")[1] or ".jpg"
    fname = f"case_{case_id}_{uuid.uuid4().hex[:8]}{ext}"
    fpath = os.path.join(_ATTACHMENT_DIR, fname)

    contents = await file.read()
    with open(fpath, "wb") as f:
        f.write(contents)

    case.attachment_path = f"/uploads/attachments/{fname}"
    case.updated_at = datetime.now()
    db.commit()
    db.refresh(case)
    return _enrich(case)
