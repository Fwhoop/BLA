from pydantic import BaseModel, EmailStr, field_validator, model_validator
from datetime import datetime, date
from typing import Optional, List


# ─────────────────────────────────────────────────────────────────────────────
# USER SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class UserBase(BaseModel):
    email: EmailStr
    username: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None

    # Legacy single address field
    address: Optional[str] = None

    # Philippine address components
    house_number: Optional[str] = None
    street_name:  Optional[str] = None
    purok:        Optional[str] = None
    city:         Optional[str] = None
    province:     Optional[str] = None
    zip_code:     Optional[str] = None

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
    house_number: Optional[str] = None
    street_name:  Optional[str] = None
    purok:        Optional[str] = None
    city:         Optional[str] = None
    province:     Optional[str] = None
    zip_code:     Optional[str] = None
    barangay_id: Optional[int] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None
    verification_status: Optional[str] = None
    profile_photo_path: Optional[str] = None


class UserRead(UserBase):
    id: int
    is_active: bool = True
    id_photo_url:        Optional[str] = None
    selfie_with_id_path: Optional[str] = None
    profile_photo_path:  Optional[str] = None
    verification_status: Optional[str] = "pending"
    verification_method: Optional[str] = None
    email_verified:  Optional[bool] = False
    mobile_verified: Optional[bool] = False
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    rejected_by: Optional[int] = None
    rejected_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    created_at: datetime

    @field_validator('is_active', mode='before')
    @classmethod
    def ensure_bool(cls, v):
        if v is None:
            return True
        return bool(v)

    class Config:
        from_attributes = True


class UserSummaryRead(BaseModel):
    total: int
    pending: int
    approved: int
    rejected: int
    active: int
    inactive: int


# ─────────────────────────────────────────────────────────────────────────────
# AUTH SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class Token(BaseModel):
    access_token: str
    token_type: str


class TokenData(BaseModel):
    username: Optional[str] = None


# ─────────────────────────────────────────────────────────────────────────────
# CASE SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class CaseBase(BaseModel):
    title: str
    description: str
    category: Optional[str] = None
    urgency: Optional[str] = "medium"


class CaseCreate(CaseBase):
    pass


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
    is_cross_barangay: bool = False
    created_at: datetime
    updated_at: Optional[datetime] = None
    reporter_name: Optional[str] = None
    reporter_email: Optional[str] = None

    class Config:
        from_attributes = True


# ─────────────────────────────────────────────────────────────────────────────
# COMPLAINT RESPONDENT SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class ComplaintRespondentCreate(BaseModel):
    respondent_id: Optional[int] = None
    respondent_barangay_id: Optional[int] = None
    respondent_name: Optional[str] = None
    respondent_address: Optional[str] = None
    is_registered_user: bool = False
    unknown_name: bool = False


class ComplaintRespondentRead(ComplaintRespondentCreate):
    id: int
    complaint_id: int
    created_at: datetime

    class Config:
        from_attributes = True


# ─────────────────────────────────────────────────────────────────────────────
# MEDIATION SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class MediationCreate(BaseModel):
    mediation_date: Optional[date] = None
    mediation_time: Optional[str] = None
    location: Optional[str] = None
    summary_notes: Optional[str] = None
    resolution_status: Optional[str] = "scheduled"
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


class MediationRead(MediationCreate):
    id: int
    complaint_id: int
    mediated_by: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# ─────────────────────────────────────────────────────────────────────────────
# BARANGAY SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class BarangayBase(BaseModel):
    name: str


class BarangayCreate(BarangayBase):
    pass


class BarangayRead(BarangayBase):
    id: int

    class Config:
        from_attributes = True


# ─────────────────────────────────────────────────────────────────────────────
# CHAT SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

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


# ─────────────────────────────────────────────────────────────────────────────
# DOCUMENT REQUEST SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

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


# ─────────────────────────────────────────────────────────────────────────────
# NOTIFICATION SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

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


# ─────────────────────────────────────────────────────────────────────────────
# ANALYTICS SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class ComplaintTypeStat(BaseModel):
    category: str
    count: int


class RespondentStat(BaseModel):
    respondent_name: str
    barangay: Optional[str] = None
    complaint_count: int


class BarangayStat(BaseModel):
    barangay: str
    complaint_count: int
    request_count: int


class AnalyticsSummary(BaseModel):
    total_complaints: int
    total_requests: int
    total_users: int
    total_barangays: int
    pending_complaints: int
    resolved_complaints: int
    complaints_by_type: List[ComplaintTypeStat]
    top_respondents: List[RespondentStat]
    complaints_by_barangay: List[BarangayStat]


# ─────────────────────────────────────────────────────────────────────────────
# OTP + VERIFICATION SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class SendEmailOTPRequest(BaseModel):
    email: str


class VerifyEmailOTPRequest(BaseModel):
    user_id: int
    otp: str


class VerifyFirebasePhoneRequest(BaseModel):
    user_id: int
    firebase_id_token: str


class ForgotPasswordRequest(BaseModel):
    identifier: str          # email or phone
    method: str              # "email" or "phone"


class ResetPasswordRequest(BaseModel):
    user_id: int
    otp: str
    new_password: str


class ResetPasswordFirebaseRequest(BaseModel):
    user_id: int
    firebase_id_token: str
    new_password: str


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN APPROVAL SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class AdminApprovalAction(BaseModel):
    reason: Optional[str] = None


class PendingAdminRead(BaseModel):
    id: int
    first_name: str
    last_name: str
    email: str
    phone: Optional[str] = None
    barangay_id: Optional[int] = None
    barangay_name: Optional[str] = None
    verification_status: str
    created_at: datetime

    class Config:
        from_attributes = True


# ─────────────────────────────────────────────────────────────────────────────
# AUDIT LOG SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

class AuditLogRead(BaseModel):
    id: int
    action_type: str
    performed_by: Optional[int] = None
    target_user_id: Optional[int] = None
    metadata: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
