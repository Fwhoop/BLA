from sqlalchemy import Boolean, Column, Integer, String, DateTime, ForeignKey, Text, Date
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from .db import Base


class Barangay(Base):
    __tablename__ = "barangays"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), unique=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    users = relationship("User", back_populates="barangay")
    requests = relationship("Request", back_populates="barangay", cascade="all, delete-orphan")


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    username = Column(String(50), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    first_name = Column(String(50), nullable=False)
    last_name = Column(String(50), nullable=False)
    phone = Column(String(20), nullable=True)

    # ── Legacy single address field (kept for backward compat) ──────────────
    address = Column(Text, nullable=True)

    # ── Philippine address components ────────────────────────────────────────
    house_number = Column(String(50), nullable=True)
    street_name  = Column(String(100), nullable=True)
    purok        = Column(String(50), nullable=True)
    city         = Column(String(100), nullable=True)
    province     = Column(String(100), nullable=True)
    zip_code     = Column(String(10), nullable=True)

    role       = Column(String(20), default="user")
    barangay_id = Column(Integer, ForeignKey("barangays.id"), nullable=True)
    is_active  = Column(Boolean, default=True)

    # ── Photo paths ──────────────────────────────────────────────────────────
    id_photo_url       = Column(String(500), nullable=True)   # Government ID
    selfie_with_id_path = Column(String(500), nullable=True)  # Selfie holding ID
    profile_photo_path  = Column(String(500), nullable=True)  # Profile/avatar photo

    # ── Verification ─────────────────────────────────────────────────────────
    verification_status = Column(String(20), default="pending")  # pending|approved|rejected
    verification_method = Column(String(50), nullable=True)       # email|sms|manual
    email_verified  = Column(Boolean, default=False)
    mobile_verified = Column(Boolean, default=False)
    approved_by  = Column(Integer, ForeignKey("users.id"), nullable=True)
    approved_at  = Column(DateTime(timezone=True), nullable=True)

    # ── Rejection tracking ───────────────────────────────────────────────────
    rejected_by     = Column(Integer, ForeignKey("users.id"), nullable=True)
    rejected_at     = Column(DateTime(timezone=True), nullable=True)
    rejection_reason = Column(String(500), nullable=True)

    # ── OTP (email verification + password reset) ────────────────────────────
    otp_code     = Column(String(255), nullable=True)   # bcrypt-hashed
    otp_expiry   = Column(DateTime(timezone=True), nullable=True)
    otp_attempts = Column(Integer, default=0)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    barangay = relationship("Barangay", back_populates="users")
    cases = relationship("Case", back_populates="reporter", cascade="all, delete-orphan")
    requests = relationship("Request", back_populates="requester", cascade="all, delete-orphan")


class Case(Base):
    __tablename__ = "cases"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=False)
    status = Column(String(20), default="pending", nullable=False)
    category = Column(String(50), nullable=True)
    urgency = Column(String(20), default="medium")
    is_cross_barangay = Column(Boolean, default=False)
    complaint_barangay_id = Column(Integer, ForeignKey("barangays.id"), nullable=True)
    reporter_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    reporter = relationship("User", back_populates="cases")
    respondents = relationship("ComplaintRespondent", back_populates="complaint", cascade="all, delete-orphan")
    mediations  = relationship("Mediation", back_populates="complaint", cascade="all, delete-orphan")


class ComplaintRespondent(Base):
    __tablename__ = "complaint_respondents"

    id = Column(Integer, primary_key=True, index=True)
    complaint_id = Column(Integer, ForeignKey("cases.id", ondelete="CASCADE"), nullable=False, index=True)
    respondent_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    respondent_barangay_id = Column(Integer, ForeignKey("barangays.id"), nullable=True)
    respondent_name    = Column(String(200), nullable=True)
    respondent_address = Column(Text, nullable=True)
    is_registered_user = Column(Boolean, default=False)
    unknown_name       = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    complaint  = relationship("Case", back_populates="respondents")
    respondent = relationship("User", foreign_keys=[respondent_id])
    barangay   = relationship("Barangay", foreign_keys=[respondent_barangay_id])


class Mediation(Base):
    __tablename__ = "mediations"

    id = Column(Integer, primary_key=True, index=True)
    complaint_id = Column(Integer, ForeignKey("cases.id", ondelete="CASCADE"), nullable=False, index=True)
    mediated_by  = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    mediation_date = Column(Date, nullable=True)
    mediation_time = Column(String(20), nullable=True)
    location       = Column(String(200), nullable=True)
    summary_notes  = Column(Text, nullable=True)
    resolution_status   = Column(String(30), default="scheduled")  # scheduled|ongoing|resolved|failed
    next_hearing_date   = Column(Date, nullable=True)
    agreement_document_path = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    complaint  = relationship("Case", back_populates="mediations")
    mediator   = relationship("User", foreign_keys=[mediated_by])


class Chat(Base):
    __tablename__ = "chats"

    id = Column(Integer, primary_key=True, index=True)
    sender_id   = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    receiver_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    message  = Column(Text, nullable=False)
    is_bot   = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    sender   = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])


class Request(Base):
    __tablename__ = "requests"

    id = Column(Integer, primary_key=True, index=True)
    requester_id  = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    barangay_id   = Column(Integer, ForeignKey("barangays.id", ondelete="CASCADE"), nullable=False)
    document_type = Column(String(100), nullable=False)
    purpose  = Column(Text, nullable=False)
    status   = Column(String(20), default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    requester = relationship("User", back_populates="requests")
    barangay  = relationship("Barangay", back_populates="requests")


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title      = Column(String(255), nullable=False)
    message    = Column(Text, nullable=False)
    notif_type = Column(String(50), default="info")
    reference_id = Column(Integer, nullable=True)
    is_read    = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", backref="notifications")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id             = Column(Integer, primary_key=True, index=True)
    action_type    = Column(String(50), nullable=False, index=True)   # e.g. "admin_approved"
    performed_by   = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    target_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    metadata       = Column(Text, nullable=True)   # JSON string
    created_at     = Column(DateTime(timezone=True), server_default=func.now())
