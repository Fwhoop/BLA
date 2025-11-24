from pydantic import BaseModel, EmailStr, field_validator, model_validator
from datetime import datetime
from typing import Optional

class UserBase(BaseModel):
    email: EmailStr
    username: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
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
    barangay_id: Optional[int] = None
    role: Optional[str] = None

class UserRead(UserBase):
    id: int
    is_active: bool = True
    created_at: datetime

    @field_validator('is_active', mode='before')
    @classmethod
    def ensure_bool(cls, v):
        """Ensure is_active is always a boolean"""
        if v is None:
            return True
        return bool(v)

    class Config:
        from_attributes = True

# AUTH SCHEMAS
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

# CASE SCHEMAS
class CaseBase(BaseModel):
    title: str
    description: str

class CaseCreate(CaseBase):
    pass

class CaseUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None

class CaseRead(CaseBase):
    id: int
    reporter_id: int
    created_at: datetime

    class Config:
        from_attributes = True

# BRGY SCHEMAS
class BarangayBase(BaseModel):
    name: str

class BarangayCreate(BarangayBase):
    pass

class BarangayRead(BarangayBase):
    id: int

    class Config:
        from_attributes = True


#CHAT SCHEMAS
class ChatCreate(BaseModel):
    sender_id: int
    receiver_id: int
    message: str

class ChatRead(ChatCreate):
    id: int
    created_at: datetime

    class Config:
        orm_mode = True

# REQUEST SCHEMAS
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
        orm_mode = True