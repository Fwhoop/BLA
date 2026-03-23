from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session
from typing import List
import os, uuid

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user

_LOGO_DIR = "uploads/logos"

router = APIRouter(prefix="/barangays", tags=["barangays"])

@router.post("/", response_model=schemas.BarangayRead)
def create_barangay(
    barangay: schemas.BarangayCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can create barangays"
        )
    new_barangay = models.Barangay(name=barangay.name)
    db.add(new_barangay)
    db.commit()
    db.refresh(new_barangay)
    return new_barangay

@router.get("/", response_model=List[schemas.BarangayRead])
def get_barangays(db: Session = Depends(get_db)):
    """Public endpoint — barangay list is needed on the signup screen."""
    return db.query(models.Barangay).all()

@router.put("/{barangay_id}", response_model=schemas.BarangayRead)
def update_barangay(
    barangay_id: int,
    updated_barangay: schemas.BarangayCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can update barangays"
        )
    barangay = db.query(models.Barangay).filter(models.Barangay.id == barangay_id).first()
    if not barangay:
        raise HTTPException(status_code=404, detail="Barangay not found")
    
    barangay.name = updated_barangay.name
    db.commit()
    db.refresh(barangay)
    return barangay

@router.get("/{barangay_id}", response_model=schemas.BarangayRead)
def get_barangay(barangay_id: int, db: Session = Depends(get_db)):
    barangay = db.query(models.Barangay).filter(models.Barangay.id == barangay_id).first()
    if not barangay:
        raise HTTPException(status_code=404, detail="Barangay not found")
    return barangay


@router.post("/{barangay_id}/logo", response_model=schemas.BarangayRead)
async def upload_barangay_logo(
    barangay_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Admin uploads the primary (left) barangay logo."""
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(status_code=403, detail="Only admins can upload logos")
    if current_user.role == "admin" and current_user.barangay_id != barangay_id:
        raise HTTPException(status_code=403, detail="Not authorized for this barangay")
    barangay = db.query(models.Barangay).filter(models.Barangay.id == barangay_id).first()
    if not barangay:
        raise HTTPException(status_code=404, detail="Barangay not found")
    os.makedirs(_LOGO_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "logo.png")[1] or ".png"
    fname = f"brgy_{barangay_id}_{uuid.uuid4().hex[:8]}{ext}"
    fpath = os.path.join(_LOGO_DIR, fname)
    contents = await file.read()
    with open(fpath, "wb") as f:
        f.write(contents)
    barangay.logo_url = f"/uploads/logos/{fname}"
    db.commit()
    db.refresh(barangay)
    return barangay


@router.post("/{barangay_id}/logo-secondary", response_model=schemas.BarangayRead)
async def upload_barangay_logo_secondary(
    barangay_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Admin uploads the secondary (right) logo — defaults to Bagong Pilipinas if not set."""
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(status_code=403, detail="Only admins can upload logos")
    if current_user.role == "admin" and current_user.barangay_id != barangay_id:
        raise HTTPException(status_code=403, detail="Not authorized for this barangay")
    barangay = db.query(models.Barangay).filter(models.Barangay.id == barangay_id).first()
    if not barangay:
        raise HTTPException(status_code=404, detail="Barangay not found")
    os.makedirs(_LOGO_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "logo.png")[1] or ".png"
    fname = f"brgy_{barangay_id}_secondary_{uuid.uuid4().hex[:8]}{ext}"
    fpath = os.path.join(_LOGO_DIR, fname)
    contents = await file.read()
    with open(fpath, "wb") as f:
        f.write(contents)
    barangay.logo_url_secondary = f"/uploads/logos/{fname}"
    db.commit()
    db.refresh(barangay)
    return barangay


@router.delete("/{barangay_id}")
def delete_barangay(
    barangay_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can delete barangays"
        )
    barangay = db.query(models.Barangay).filter(models.Barangay.id == barangay_id).first()
    if not barangay:
        raise HTTPException(status_code=404, detail="Barangay not found")
    
    db.delete(barangay)
    db.commit()
    return {"detail": "Barangay deleted successfully"}
