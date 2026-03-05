from sqlalchemy import Boolean, Column, Date, Index, Integer, String, DateTime, ForeignKey, Text
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
    email = Column(String(255), unique=True, index=True, nullable=True)   # nullable: SMS-only users
    username = Column(String(50), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    first_name = Column(String(50), nullable=False)
    last_name = Column(String(50), nullable=False)
    phone = Column(String(20), nullable=True)
    role = Column(String(20), default="user")
    barangay_id = Column(Integer, ForeignKey("barangays.id"), nullable=True)
    is_active = Column(Boolean, default=False)   # False until verified/approved

    # ── ID Verification ──────────────────────────────────────────────────────
    verification_status = Column(String(30), default="pending_verification")
    # values: pending_verification | approved | rejected
    verification_method = Column(String(10), default="email")   # email | sms
    id_photo_url = Column(String(500), nullable=True)
    selfie_with_id_url = Column(String(500), nullable=True)
    profile_photo_url = Column(String(500), nullable=True)
    # SMS OTP fields (dev mode)
    sms_otp_hash = Column(String(64), nullable=True)
    sms_otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    # Approval audit trail
    approved_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    approved_at = Column(DateTime(timezone=True), nullable=True)

    # ── Address (structured, PH standard) ────────────────────────────────────
    address = Column(Text, nullable=True)           # deprecated – kept for backward compat
    house_no = Column(String(20), nullable=True)
    street_name = Column(String(100), nullable=True)
    purok_sitio = Column(String(100), nullable=True)
    city_municipality = Column(String(100), nullable=True)
    province = Column(String(100), nullable=True)
    zip_code = Column(String(10), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    barangay = relationship("Barangay", back_populates="users")
    cases = relationship("Case", back_populates="reporter", cascade="all, delete-orphan")
    requests = relationship("Request", back_populates="requester", cascade="all, delete-orphan")
    respondent_entries = relationship("CaseRespondent", back_populates="respondent_user",
                                      foreign_keys="CaseRespondent.respondent_user_id")
    approver = relationship("User", foreign_keys=[approved_by], remote_side="User.id")

    __table_args__ = (
        Index("ix_users_verification_status", "verification_status"),
        Index("ix_users_phone", "phone"),
    )


class Case(Base):
    __tablename__ = "cases"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=False)
    status = Column(String(30), default="pending", nullable=False)
    # values: pending | reviewing | under_mediation | resolved | dismissed
    reporter_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    # ── Complaint extensions ──────────────────────────────────────────────────
    category = Column(String(50), nullable=True)
    # Noise | Drugs | Property | Harassment | Violence | Theft | Environmental | Adultery | Agaw Asawa | Other
    urgency = Column(String(20), default="medium")      # low | medium | high
    is_cross_barangay = Column(Boolean, default=False)
    complaint_barangay_id = Column(Integer, ForeignKey("barangays.id"), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    reporter = relationship("User", back_populates="cases")
    respondents = relationship("CaseRespondent", back_populates="case", cascade="all, delete-orphan")
    mediations = relationship("Mediation", back_populates="case")
    complaint_barangay = relationship("Barangay", foreign_keys=[complaint_barangay_id])

    __table_args__ = (
        Index("ix_cases_category", "category"),
        Index("ix_cases_status", "status"),
        Index("ix_cases_reporter_id", "reporter_id"),
    )


class CaseRespondent(Base):
    __tablename__ = "case_respondents"

    id = Column(Integer, primary_key=True, index=True)
    case_id = Column(Integer, ForeignKey("cases.id", ondelete="CASCADE"), nullable=False)
    respondent_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    respondent_name = Column(String(200), nullable=True)
    respondent_alias = Column(String(100), nullable=True)
    respondent_description = Column(Text, nullable=True)
    respondent_barangay_id = Column(Integer, ForeignKey("barangays.id"), nullable=True)
    respondent_address = Column(String(255), nullable=True)
    respondent_gender = Column(String(20), nullable=True)
    is_registered_user = Column(Boolean, default=False)
    name_unknown = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    case = relationship("Case", back_populates="respondents")
    respondent_user = relationship("User", back_populates="respondent_entries",
                                   foreign_keys=[respondent_user_id])
    respondent_barangay = relationship("Barangay", foreign_keys=[respondent_barangay_id])

    __table_args__ = (
        Index("ix_case_respondents_case_id", "case_id"),
        Index("ix_case_respondents_respondent_user_id", "respondent_user_id"),
    )


class Mediation(Base):
    __tablename__ = "mediations"

    id = Column(Integer, primary_key=True, index=True)
    case_id = Column(Integer, ForeignKey("cases.id"), nullable=False)
    mediated_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    mediation_date = Column(Date, nullable=False)
    mediation_time = Column(String(20), nullable=False)
    location = Column(String(255), nullable=False)
    summary_notes = Column(Text, nullable=True)
    resolution_status = Column(String(30), nullable=False)
    # values: ongoing | resolved | failed | adjourned
    next_hearing_date = Column(Date, nullable=True)
    agreement_document_path = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    case = relationship("Case", back_populates="mediations")
    mediator = relationship("User", foreign_keys=[mediated_by])


class Chat(Base):
    __tablename__ = "chats"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    receiver_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    message = Column(Text, nullable=False)
    is_bot = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])


class Request(Base):
    __tablename__ = "requests"

    id = Column(Integer, primary_key=True, index=True)
    requester_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    barangay_id = Column(Integer, ForeignKey("barangays.id", ondelete="CASCADE"), nullable=False)
    document_type = Column(String(100), nullable=False)
    purpose = Column(Text, nullable=False)
    status = Column(String(20), default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    requester = relationship("User", back_populates="requests")
    barangay = relationship("Barangay", back_populates="requests")


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token_hash = Column(String(64), unique=True, index=True, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title = Column(String(255), nullable=False)
    message = Column(Text, nullable=False)
    notif_type = Column(String(50), default="info")
    reference_id = Column(Integer, nullable=True)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", backref="notifications")
