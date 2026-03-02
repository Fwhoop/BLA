from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/cases", tags=["cases"])


def _enrich(case: models.Case) -> dict:
    """Add reporter_name and reporter_email to a case dict."""
    d = {
        "id": case.id,
        "title": case.title,
        "description": case.description,
        "status": case.status if case.status else "pending",
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
        status="pending",
        reporter_id=current_user.id
    )
    db.add(new_case)
    db.commit()
    db.refresh(new_case)
    return _enrich(new_case)


@router.get("/", response_model=List[schemas.CaseRead])
def get_cases(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role == "superadmin":
        cases = db.query(models.Case).order_by(models.Case.created_at.desc()).all()
    elif current_user.role == "admin":
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
    elif current_user.role == "admin":
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
    elif current_user.role == "admin":
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Not authorized to update cases from other barangays")

    for key, value in updated_case.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(case, key, value)

    db.commit()
    db.refresh(case)
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
