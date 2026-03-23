"""SMS delivery via Semaphore (semaphore.co.ph) — Philippine SMS gateway."""
import requests
from ..core.config import settings


def send_sms(phone: str, message: str) -> bool:
    """Send an SMS via Semaphore. Returns True on success, False if not configured or failed."""
    api_key = settings.semaphore_api_key
    if not api_key:
        print("[SMS] SEMAPHORE_API_KEY not set — skipping SMS send.")
        return False
    try:
        resp = requests.post(
            "https://api.semaphore.co/api/v4/messages",
            data={
                "apikey": api_key,
                "number": phone,
                "message": message,
                "sendername": settings.semaphore_sender_name,
            },
            timeout=15,
        )
        if resp.status_code == 200:
            print(f"[SMS] Sent to {phone}")
            return True
        print(f"[SMS] Semaphore error {resp.status_code}: {resp.text}")
        return False
    except Exception as e:
        print(f"[SMS] Exception: {e}")
        return False


def send_password_reset_sms(phone: str, otp: str) -> bool:
    message = (
        f"Your Barangay Legal Aid password reset code is: {otp}. "
        "It expires in 5 minutes. Do not share this code."
    )
    return send_sms(phone, message)
