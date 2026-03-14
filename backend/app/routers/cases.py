from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/cases", tags=["cases"])


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
        "reporter_id": case.reporter_id,
        "created_at": case.created_at,
        "updated_at": case.updated_at,
        "reporter_name": None,
        "reporter_email": None,
    }
    if case.reporter:
        d["reporter_name"] = f"{case.reporter.first_name} {case.reporter.last_name}".strip()
        d["reporter_email"] = case.reporter.email
    return d


@router.post("/", response_model=schemas.CaseRead)
def create_case(
    case: schemas.CaseCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    new_case = models.Case(
        title=case.title,
        description=case.description,
        category=case.category,
        urgency=case.urgency or "medium",
        status="pending",
        reporter_id=current_user.id,
    )
    db.add(new_case)
    db.commit()
    db.refresh(new_case)

    # Notify all active admins and staff in the reporter's barangay about the new case
    if current_user.barangay_id:
        admins = db.query(models.User).filter(
            models.User.barangay_id == current_user.barangay_id,
            models.User.role.in_(["admin", "superadmin", "staff"]),
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

    return _enrich(new_case)


@router.get("/", response_model=List[schemas.CaseRead])
def get_cases(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role == "superadmin":
        cases = db.query(models.Case).order_by(models.Case.created_at.desc()).all()
    elif current_user.role in ("admin", "staff"):
        if not current_user.barangay_id:
            return []
        cases = (
            db.query(models.Case)
            .join(models.User, models.Case.reporter_id == models.User.id)
            .filter(models.User.barangay_id == current_user.barangay_id)
            .order_by(models.Case.created_at.desc())
            .all()
        )
    else:
        cases = (
            db.query(models.Case)
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
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == "user":
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to view this case")
    elif current_user.role in ("admin", "staff"):
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
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
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == "user":
        # Users can only edit their own cases (not status)
        if case.reporter_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to update this case")
        # Users cannot change status
        updated_case.status = None
    elif current_user.role in ("admin", "staff"):
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to update cases from other barangays")

    old_status = case.status
    updates = updated_case.model_dump(exclude_unset=True)

    # Enforce: cannot mark Resolved without at least one mediation record
    if updates.get("status") == "resolved":
        mediation_count = db.query(models.Mediation).filter(
            models.Mediation.complaint_id == case_id
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
        and current_user.role in ("admin", "superadmin", "staff")
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

    # Staff cannot delete cases
    if current_user.role == "staff":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Staff cannot delete cases")

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
