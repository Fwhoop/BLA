"""
Reset all users and create a fresh superadmin.
Run on Railway: railway run python reset_and_seed.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db import SessionLocal
from app.models import User, Notification, Chat, Case, Request
import bcrypt
from datetime import datetime, timezone

def get_password_hash(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

def reset_and_seed():
    db = SessionLocal()
    try:
        print("Deleting all notifications...")
        db.query(Notification).delete()

        print("Deleting all chats...")
        db.query(Chat).delete()

        print("Deleting all cases...")
        db.query(Case).delete()

        print("Deleting all requests...")
        db.query(Request).delete()

        print("Deleting all users...")
        db.query(User).delete()

        db.commit()
        print("All users and related data deleted.")

        # Create fresh superadmin
        superadmin = User(
            email="superadmin@bla.com",
            username="superadmin",
            hashed_password=get_password_hash("SuperAdmin@2024"),
            first_name="Super",
            last_name="Admin",
            role="superadmin",
            barangay_id=None,
            is_active=True,
            created_at=datetime.now(timezone.utc),
        )
        db.add(superadmin)
        db.commit()

        print("\n✅ Done.")
        print("─────────────────────────────────")
        print("  Email   : superadmin@bla.com")
        print("  Password: SuperAdmin@2024")
        print("  Role    : superadmin")
        print("─────────────────────────────────")

    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    reset_and_seed()
