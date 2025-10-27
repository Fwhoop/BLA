from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/requests", tags=["requests"])

@router.post("/", response_model=schemas.RequestRead)
def create_request(
    request: schemas.RequestCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Create a new document request"""
    new_request = models.Request(
        requester_id=current_user.id,
        barangay_id=request.barangay_id,
        document_type=request.document_type,
        purpose=request.purpose,
        status="pending"
    )
    db.add(new_request)
    db.commit()
    db.refresh(new_request)
    return new_request

@router.get("/", response_model=List[schemas.RequestRead])
def get_requests(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get all requests - filtered by role"""
    if current_user.role == "superadmin":
        return db.query(models.Request).all()
    elif current_user.role == "admin":
        # Admins only see requests from their barangay
        if not current_user.barangay_id:
            return []
        return db.query(models.Request).filter(
            models.Request.barangay_id == current_user.barangay_id
        ).all()
    else:
        # Users only see their own requests
        return db.query(models.Request).filter(
            models.Request.requester_id == current_user.id
        ).all()

@router.get("/{request_id}", response_model=schemas.RequestRead)
def get_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get a specific request"""
    request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")
    
    # Check permissions
    if current_user.role == "user":
        if request.requester_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
    elif current_user.role == "admin":
        if request.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    
    return request

@router.put("/{request_id}", response_model=schemas.RequestRead)
def update_request(
    request_id: int,
    request_update: schemas.RequestUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Update request status (only for admins)"""
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(status_code=403, detail="Only admins can update requests")
    
    request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")
    
    # Check if admin is from the same barangay
    if current_user.role == "admin":
        if request.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized for this barangay")
    
    if request_update.status:
        request.status = request_update.status
        request.updated_at = datetime.now()
    
    db.commit()
    db.refresh(request)
    return request

@router.delete("/{request_id}")
def delete_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Delete a request"""
    request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")
    
    # Check permissions
    if current_user.role == "user" and request.requester_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    
    if current_user.role == "admin" and request.barangay_id != current_user.barangay_id:
        raise HTTPException(status_code=403, detail="Not authorized for this barangay")
    
    db.delete(request)
    db.commit()
    return {"detail": "Request deleted successfully"}

