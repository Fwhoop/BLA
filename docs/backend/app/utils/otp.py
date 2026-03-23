"""OTP generation and verification utilities."""
import random
import string
import bcrypt


def generate_otp() -> str:
    """Generate a 6-digit numeric OTP."""
    return ''.join(random.choices(string.digits, k=6))


def hash_otp(otp: str) -> str:
    """Hash OTP using bcrypt before storing."""
    return bcrypt.hashpw(otp.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def verify_otp(plain: str, hashed: str) -> bool:
    """Verify a plain OTP against its bcrypt hash."""
    try:
        return bcrypt.checkpw(plain.encode('utf-8'), hashed.encode('utf-8'))
    except Exception:
        return False
