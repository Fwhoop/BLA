from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/cases", tags=["cases"])

@router.post("/", response_model=schemas.CaseRead)
def create_case(
    case: schemas.CaseCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    new_case = models.Case(
        title=case.title,
        description=case.description,
        reporter_id=current_user.id
    )
    db.add(new_case)
    db.commit()
    db.refresh(new_case)
    return new_case

@router.get("/", response_model=List[schemas.CaseRead])
def get_cases(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get all cases - filtered by role"""
    if current_user.role == "superadmin":
        return db.query(models.Case).all()
    elif current_user.role == "admin":
        if not current_user.barangay_id:
            return []
        return db.query(models.Case).join(models.User).filter(
            models.User.barangay_id == current_user.barangay_id
        ).all()
    else:
        return db.query(models.Case).filter(
            models.Case.reporter_id == current_user.id
        ).all()

@router.get("/{case_id}", response_model=schemas.CaseRead)
def get_case(
    case_id: int, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    
    # Check permissions
    if current_user.role == "user":
        # Users can only see their own cases
        if case.reporter_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to view this case"
            )
    elif current_user.role == "admin":
        # Admins can only see cases from users in their barangay
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to view cases from other barangays"
            )
    
    return case

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
    
    # Check permissions
    if current_user.role == "user":
        # Users can only update their own cases
        if case.reporter_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to update this case"
            )
    elif current_user.role == "admin":
        # Admins can only update cases from users in their barangay
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to update cases from other barangays"
            )

    for key, value in updated_case.dict(exclude_unset=True).items():
        setattr(case, key, value)

    db.commit()
    db.refresh(case)
    return case

@router.delete("/{case_id}")
def delete_case(
    case_id: int, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    case = db.query(models.Case).filter(models.Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    
    # Check permissions
    if current_user.role == "user":
        # Users can only delete their own cases
        if case.reporter_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to delete this case"
            )
    elif current_user.role == "admin":
        # Admins can only delete cases from users in their barangay
        reporter = db.query(models.User).filter(models.User.id == case.reporter_id).first()
        if not reporter or reporter.barangay_id != current_user.barangay_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to delete cases from other barangays"
            )
    
    db.delete(case)
    db.commit()
    return {"detail": "Case deleted successfully"}
