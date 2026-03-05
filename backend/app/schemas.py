from pydantic import BaseModel, EmailStr, field_validator
from datetime import datetime, date
from typing import Optional, List


# ── USER SCHEMAS ──────────────────────────────────────────────────────────────

class UserBase(BaseModel):
    email: Optional[EmailStr] = None      # nullable: SMS-only users
    username: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    # deprecated single address field (kept for backward compat)
    address: Optional[str] = None
    # structured Philippine address
    house_no: Optional[str] = None
    street_name: Optional[str] = None
    purok_sitio: Optional[str] = None
    city_municipality: Optional[str] = None
    province: Optional[str] = None
    zip_code: Optional[str] = None
    barangay_id: Optional[int] = None
    role: Optional[str] = "user"


class UserCreate(UserBase):
    password: str


class UserUpdate(BaseModel):
    email: Optional[EmailStr] = None
    username: Optional[str] = None
    password: Optional[str] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    house_no: Optional[str] = None
    street_name: Optional[str] = None
    purok_sitio: Optional[str] = None
    city_municipality: Optional[str] = None
    province: Optional[str] = None
    zip_code: Optional[str] = None
    barangay_id: Optional[int] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None
    verification_status: Optional[str] = None


class UserRead(UserBase):
    id: int
    is_active: bool = True
    verification_status: str = "pending_verification"
    verification_method: str = "email"
    id_photo_url: Optional[str] = None
    selfie_with_id_url: Optional[str] = None
    profile_photo_url: Optional[str] = None
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    created_at: datetime

    @field_validator('is_active', mode='before')
    @classmethod
    def ensure_bool(cls, v):
        if v is None:
            return True
        return bool(v)

    class Config:
        from_attributes = True


# ── AUTH SCHEMAS ──────────────────────────────────────────────────────────────

class Token(BaseModel):
    access_token: str
    token_type: str


class TokenData(BaseModel):
    username: Optional[str] = None


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


# ── CASE / COMPLAINT SCHEMAS ───────────────────────────────────────────────────

class CaseRespondentCreate(BaseModel):
    respondent_user_id: Optional[int] = None
    respondent_name: Optional[str] = None
    respondent_alias: Optional[str] = None
    respondent_description: Optional[str] = None
    respondent_barangay_id: Optional[int] = None
    respondent_address: Optional[str] = None
    respondent_gender: Optional[str] = None
    is_registered_user: bool = False
    name_unknown: bool = False


class CaseRespondentRead(BaseModel):
    id: int
    case_id: int
    respondent_user_id: Optional[int] = None
    respondent_name: Optional[str] = None
    respondent_alias: Optional[str] = None
    respondent_description: Optional[str] = None
    respondent_barangay_id: Optional[int] = None
    respondent_barangay_name: Optional[str] = None
    respondent_address: Optional[str] = None
    respondent_gender: Optional[str] = None
    is_registered_user: bool
    name_unknown: bool
    registered_user_name: Optional[str] = None   # populated from respondent_user if registered
    previous_complaint_count: Optional[int] = None

    class Config:
        from_attributes = True


class CaseBase(BaseModel):
    title: str
    description: str


class CaseCreate(CaseBase):
    category: Optional[str] = None
    urgency: Optional[str] = "medium"
    is_cross_barangay: Optional[bool] = False
    complaint_barangay_id: Optional[int] = None
    respondents: Optional[List[CaseRespondentCreate]] = []


class CaseUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    category: Optional[str] = None
    urgency: Optional[str] = None


class CaseRead(CaseBase):
    id: int
    reporter_id: int
    status: str = "pending"
    category: Optional[str] = None
    urgency: Optional[str] = "medium"
    is_cross_barangay: bool = False
    complaint_barangay_id: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
    reporter_name: Optional[str] = None
    reporter_email: Optional[str] = None
    respondents: List[CaseRespondentRead] = []
    mediation_count: int = 0

    class Config:
        from_attributes = True


# ── MEDIATION SCHEMAS ─────────────────────────────────────────────────────────

class MediationCreate(BaseModel):
    case_id: int
    mediation_date: date
    mediation_time: str
    location: str
    summary_notes: Optional[str] = None
    resolution_status: str   # ongoing | resolved | failed | adjourned
    next_hearing_date: Optional[date] = None
    agreement_document_path: Optional[str] = None


class MediationUpdate(BaseModel):
    mediation_date: Optional[date] = None
    mediation_time: Optional[str] = None
    location: Optional[str] = None
    summary_notes: Optional[str] = None
    resolution_status: Optional[str] = None
    next_hearing_date: Optional[date] = None
    agreement_document_path: Optional[str] = None


class MediationRead(BaseModel):
    id: int
    case_id: int
    mediated_by: int
    mediator_name: Optional[str] = None
    mediation_date: date
    mediation_time: str
    location: str
    summary_notes: Optional[str] = None
    resolution_status: str
    next_hearing_date: Optional[date] = None
    agreement_document_path: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


# ── BARANGAY SCHEMAS ──────────────────────────────────────────────────────────

class BarangayBase(BaseModel):
    name: str


class BarangayCreate(BarangayBase):
    pass


class BarangayRead(BarangayBase):
    id: int

    class Config:
        from_attributes = True


# ── CHAT SCHEMAS ──────────────────────────────────────────────────────────────

class ChatCreate(BaseModel):
    sender_id: int
    receiver_id: int
    message: str


class ChatRead(ChatCreate):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class HistoryEntry(BaseModel):
    role: str
    content: str


class AiChatCreate(BaseModel):
    sender_id: int
    receiver_id: int
    message: str
    history: Optional[List[HistoryEntry]] = None


# ── REQUEST SCHEMAS ───────────────────────────────────────────────────────────

class RequestBase(BaseModel):
    document_type: str
    purpose: str
    barangay_id: int


class RequestCreate(RequestBase):
    pass


class RequestUpdate(BaseModel):
    status: Optional[str] = None


class RequestRead(RequestBase):
    id: int
    requester_id: int
    status: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ── NOTIFICATION SCHEMAS ──────────────────────────────────────────────────────

class NotificationRead(BaseModel):
    id: int
    user_id: int
    title: str
    message: str
    notif_type: str
    reference_id: Optional[int] = None
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UnreadCountRead(BaseModel):
    count: int
