"""Firebase Admin SDK — lazy singleton initialization."""
import json
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

_firebase_app = None


def get_firebase_app():
    """Return the Firebase Admin app, initializing it on first call."""
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    creds_json = os.environ.get("FIREBASE_CREDENTIALS_JSON", "")
    if not creds_json:
        logger.warning("[FIREBASE] FIREBASE_CREDENTIALS_JSON not set — Firebase features disabled")
        return None

    try:
        import firebase_admin
        from firebase_admin import credentials

        creds_dict = json.loads(creds_json)
        cred = credentials.Certificate(creds_dict)
        _firebase_app = firebase_admin.initialize_app(cred)
        logger.info("[FIREBASE] Firebase Admin SDK initialized")
        return _firebase_app
    except Exception as e:
        logger.warning("[FIREBASE] Failed to initialize: %s", e)
        return None


def verify_firebase_token(id_token: str) -> Optional[dict]:
    """
    Verify a Firebase ID token and return decoded claims.
    Returns None if Firebase is not configured or token is invalid.
    Raises ValueError with a user-facing message on verification failure.
    """
    app = get_firebase_app()
    if app is None:
        raise ValueError("Firebase is not configured on this server.")

    try:
        from firebase_admin import auth
        decoded = auth.verify_id_token(id_token)
        return decoded
    except Exception as e:
        logger.warning("[FIREBASE] Token verification failed: %s", e)
        raise ValueError(f"Invalid or expired Firebase token: {e}")
