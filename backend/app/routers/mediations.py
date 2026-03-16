"""
Mediations router — thin delegation layer.

All business logic lives in app/services/mediation_service.py.
Routers only handle:
  • HTTP method + path declaration
  • dependency injection (auth, db)
  • role guard
  • calling the service and returning its result
"""

from fastapi import APIRouter, Depends, status, UploadFile, File
from sqlalchemy.orm import Session
from typing import List

from .. import models, schemas
from ..db import get_db
from ..routers.auth import get_current_user
from ..services import mediation_service as svc
from fastapi import HTTPException

router = APIRouter(tags=["mediations"])


def _require_admin(current_user: models.User) -> None:
    if current_user.role not in ("admin", "staff", "superadmin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only staff or admins can manage mediation records",
        )


# ── GET /cases/{case_id}/mediations ──────────────────────────────────────────
@router.get("/cases/{case_id}/mediations", response_model=List[schemas.MediationRead])
def list_mediations(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    return svc.list_mediations(db, case_id, current_user)


# ── POST /cases/{case_id}/mediations ─────────────────────────────────────────
@router.post("/cases/{case_id}/mediations", response_model=schemas.MediationRead)
def create_mediation(
    case_id: int,
    payload: schemas.MediationCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)
    return svc.schedule_mediation(db, case_id, payload, current_user)


# ── PUT /mediations/{mediation_id} ───────────────────────────────────────────
@router.put("/mediations/{mediation_id}", response_model=schemas.MediationRead)
def update_mediation(
    mediation_id: int,
    payload: schemas.MediationUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)
    return svc.update_mediation(db, mediation_id, payload)


# ── DELETE /mediations/{mediation_id} ────────────────────────────────────────
@router.delete("/mediations/{mediation_id}")
def delete_mediation(
    mediation_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    _require_admin(current_user)
    return svc.delete_mediation(db, mediation_id)


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
    contents = await file.read()
    return svc.save_resolution_photo(db, mediation_id, contents, file.filename or "photo.jpg")
