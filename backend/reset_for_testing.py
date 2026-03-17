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

from sqlalchemy import text
from app.db import SessionLocal


def reset_for_testing():
    db = SessionLocal()
    try:
        # ── 1. Find the superadmin via raw SQL — we keep this account ──────────
        row = db.execute(
            text("SELECT id, email FROM users WHERE role = 'superadmin' LIMIT 1")
        ).fetchone()

        if not row:
            print("❌ No superadmin account found. Aborting — nothing was deleted.")
            return

        superadmin_id, superadmin_email = row[0], row[1]
        print(f"✅ Superadmin found: {superadmin_email} — this account will be kept.\n")

        confirm = input(
            "⚠️  This will DELETE all barangays, admins, users, complaints, "
            "requests, chats, and notifications.\n"
            "Type  YES  to continue: "
        ).strip()
        if confirm != "YES":
            print("Aborted. Nothing was changed.")
            return

        # ── 2. Delete via raw SQL to avoid model/schema mismatch errors ─────────
        deleted = {}

        statements = [
            ("audit_logs",           "DELETE FROM audit_logs"),
            ("notifications",        "DELETE FROM notifications"),
            ("chats",                "DELETE FROM chats"),
            ("mediations",           "DELETE FROM mediations"),
            ("complaint_respondents","DELETE FROM complaint_respondents"),
            ("cases",                "DELETE FROM cases"),
            ("requests",             "DELETE FROM requests"),
            ("users",                f"DELETE FROM users WHERE id != {superadmin_id}"),
            ("barangays",            "DELETE FROM barangays"),
        ]

        for label, sql in statements:
            result = db.execute(text(sql))
            deleted[label] = result.rowcount

        db.commit()

        # ── 5. Summary ────────────────────────────────────────────────────────
        print("\n✅ Reset complete! Records deleted:\n")
        for table, count in deleted.items():
            print(f"   {table:<30} {count:>4} row(s) deleted")

        print(f"\n🔑 Superadmin kept: {superadmin_email}")
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
