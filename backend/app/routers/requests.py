from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
import os, uuid

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

router = APIRouter(prefix="/requests", tags=["requests"])

_UPLOAD_DIR = "uploads/documents"


def _enrich(req: models.Request) -> dict:
    d = {
        "id": req.id,
        "document_type": req.document_type,
        "purpose": req.purpose,
        "barangay_id": req.barangay_id,
        "requester_id": req.requester_id,
        "status": req.status if req.status else "pending",
        "file_url": req.file_url,
        "created_at": req.created_at,
        "updated_at": req.updated_at,
        "requester_name": None,
        "requester_email": None,
    }
    if req.requester:
        d["requester_name"] = f"{req.requester.first_name} {req.requester.last_name}".strip()
        d["requester_email"] = req.requester.email
    return d


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

    # Notify all active admins and staff in this barangay about the new request
    admins = db.query(models.User).filter(
        models.User.barangay_id == new_request.barangay_id,
        models.User.role.in_(["admin", "superadmin", "staff"]),
        models.User.is_active == True,
    ).all()
    for admin in admins:
        db.add(models.Notification(
            user_id=admin.id,
            title="New Document Request",
            message=(
                f"{current_user.first_name} {current_user.last_name} "
                f"requested '{new_request.document_type}'."
            ),
            notif_type="new_request",
            reference_id=new_request.id,
        ))
    if admins:
        db.commit()

    return _enrich(new_request)


@router.get("/", response_model=List[schemas.RequestRead])
def get_requests(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Get all requests - filtered by role"""
    try:
        if current_user.role == "superadmin":
            reqs = db.query(models.Request).order_by(models.Request.created_at.desc()).all()
        elif current_user.role in ("admin", "staff"):
            if not current_user.barangay_id:
                return []
            reqs = db.query(models.Request).filter(
                models.Request.barangay_id == current_user.barangay_id
            ).order_by(models.Request.created_at.desc()).all()
        else:
            reqs = db.query(models.Request).filter(
                models.Request.requester_id == current_user.id
            ).order_by(models.Request.created_at.desc()).all()
        return [_enrich(r) for r in reqs]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error fetching requests: {str(e)}"
        )


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

    if current_user.role == "user":
        if request.requester_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
    elif current_user.role in ("admin", "staff"):
        if request.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized")

    return _enrich(request)


@router.put("/{request_id}", response_model=schemas.RequestRead)
def update_request(
    request_id: int,
    request_update: schemas.RequestUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Update request status and/or file_url (admins and staff)"""
    if current_user.role not in ["admin", "superadmin", "staff"]:
        raise HTTPException(status_code=403, detail="Only admins/staff can update requests")

    request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")

    if current_user.role in ("admin", "staff"):
        if request.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized for this barangay")

    if request_update.status:
        request.status = request_update.status
    if request_update.file_url is not None:
        request.file_url = request_update.file_url
    request.updated_at = datetime.now()

    db.commit()
    db.refresh(request)

    # Notify the requester when admin approves, rejects, or attaches a document
    if request_update.status in ("approved", "rejected"):
        labels = {"approved": "approved ✓", "rejected": "rejected ✗"}
        db.add(models.Notification(
            user_id=request.requester_id,
            title=f"Request {request_update.status.capitalize()}",
            message=(
                f"Your request for '{request.document_type}' has been "
                f"{labels[request_update.status]}."
            ),
            notif_type="request_update",
            reference_id=request.id,
        ))
        db.commit()
    elif request_update.file_url:
        db.add(models.Notification(
            user_id=request.requester_id,
            title="Document Ready",
            message=f"Your '{request.document_type}' document is ready for download.",
            notif_type="request_update",
            reference_id=request.id,
        ))
        db.commit()

    return _enrich(request)


@router.post("/{request_id}/upload-document", response_model=schemas.RequestRead)
async def upload_document(
    request_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Admin uploads the fulfilled document file for a request."""
    if current_user.role not in ["admin", "superadmin", "staff"]:
        raise HTTPException(status_code=403, detail="Only admins/staff can upload documents")

    request = db.query(models.Request).filter(models.Request.id == request_id).first()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")

    if current_user.role in ("admin", "staff"):
        if request.barangay_id != current_user.barangay_id:
            raise HTTPException(status_code=403, detail="Not authorized for this barangay")

    os.makedirs(_UPLOAD_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "doc.pdf")[1] or ".pdf"
    fname = f"req_{request_id}_{uuid.uuid4().hex[:8]}{ext}"
    fpath = os.path.join(_UPLOAD_DIR, fname)

    contents = await file.read()
    with open(fpath, "wb") as f:
        f.write(contents)

    request.file_url = f"/uploads/documents/{fname}"
    request.status = "approved"
    request.updated_at = datetime.now()
    db.commit()
    db.refresh(request)

    # Notify requester
    db.add(models.Notification(
        user_id=request.requester_id,
        title="Document Ready for Download",
        message=f"Your '{request.document_type}' document has been prepared and is ready to download.",
        notif_type="request_update",
        reference_id=request.id,
    ))
    db.commit()

    return _enrich(request)


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

    if current_user.role == "staff":
        raise HTTPException(status_code=403, detail="Staff cannot delete requests")

    if current_user.role == "user" and request.requester_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    if current_user.role == "admin" and request.barangay_id != current_user.barangay_id:
        raise HTTPException(status_code=403, detail="Not authorized for this barangay")

    db.delete(request)
    db.commit()
    return {"detail": "Request deleted successfully"}
