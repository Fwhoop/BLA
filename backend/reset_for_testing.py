"""
reset_for_testing.py
--------------------
Clears ALL data except the superadmin account so the system is clean
for user testing. Barangays, admin accounts, regular users, complaints,
requests, chats, mediations, and notifications are all removed.

Usage:
    python reset_for_testing.py

The superadmin can then log in and create fresh barangays + admin accounts
via the SuperAdmin Dashboard.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db import SessionLocal
from app.models import (
    User, Barangay, Case, ComplaintRespondent,
    Mediation, Chat, Request, Notification, AuditLog,
)


def reset_for_testing():
    db = SessionLocal()
    try:
        # ── 1. Find the superadmin — we keep this account ────────────────────
        superadmin = db.query(User).filter(User.role == "superadmin").first()
        if not superadmin:
            print("❌ No superadmin account found. Aborting — nothing was deleted.")
            return

        print(f"✅ Superadmin found: {superadmin.email} — this account will be kept.\n")

        confirm = input(
            "⚠️  This will DELETE all barangays, admins, users, complaints, "
            "requests, chats, and notifications.\n"
            "Type  YES  to continue: "
        ).strip()
        if confirm != "YES":
            print("Aborted. Nothing was changed.")
            return

        superadmin_id = superadmin.id

        # ── 2. Delete dependent records first (FK order) ──────────────────────
        deleted = {}

        deleted["audit_logs"]            = db.query(AuditLog).delete(synchronize_session=False)
        deleted["notifications"]          = db.query(Notification).delete(synchronize_session=False)
        deleted["chats"]                  = db.query(Chat).delete(synchronize_session=False)
        deleted["mediations"]             = db.query(Mediation).delete(synchronize_session=False)
        deleted["complaint_respondents"]  = db.query(ComplaintRespondent).delete(synchronize_session=False)
        deleted["cases"]                  = db.query(Case).delete(synchronize_session=False)
        deleted["requests"]               = db.query(Request).delete(synchronize_session=False)

        # ── 3. Delete all users EXCEPT superadmin ─────────────────────────────
        deleted["users"] = (
            db.query(User)
            .filter(User.id != superadmin_id)
            .delete(synchronize_session=False)
        )

        # ── 4. Delete all barangays ───────────────────────────────────────────
        deleted["barangays"] = db.query(Barangay).delete(synchronize_session=False)

        db.commit()

        # ── 5. Summary ────────────────────────────────────────────────────────
        print("\n✅ Reset complete! Records deleted:\n")
        for table, count in deleted.items():
            print(f"   {table:<30} {count:>4} row(s) deleted")

        print(f"\n🔑 Superadmin kept: {superadmin.email}")
        print("\nNext steps:")
        print("  1. Log in as superadmin")
        print("  2. Create barangays via the SuperAdmin Dashboard")
        print("  3. Create admin accounts for each barangay")
        print("  4. Residents can register fresh accounts in the app\n")

    except Exception as e:
        db.rollback()
        print(f"\n❌ Error during reset: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    reset_for_testing()
