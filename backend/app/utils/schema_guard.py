"""
Schema drift protection.

On every startup, inspects the live database tables and:
  1. Adds any missing required columns (ALTER TABLE ADD COLUMN).
  2. Cleans up stale columns left by previous migrations.
  3. Ensures NOT NULL columns that should be nullable are corrected.

Each repair runs in its own independent transaction so one failure
cannot prevent repairs on other tables.
"""

import logging
from sqlalchemy import inspect, text
from app.db import engine

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Required columns: {table: {column: ALTER TABLE DDL}}
# The canonical source of truth for every column the application uses.
# ---------------------------------------------------------------------------
REQUIRED_COLUMNS: dict[str, dict[str, str]] = {
    "mediations": {
        # Primary FK — case_id is the real column name in the production DB
        "case_id": (
            "ALTER TABLE mediations "
            "ADD COLUMN case_id INT NULL"
        ),
        "mediated_by": (
            "ALTER TABLE mediations ADD COLUMN mediated_by INT NULL"
        ),
        "mediation_date": (
            "ALTER TABLE mediations ADD COLUMN mediation_date DATE NULL"
        ),
        "mediation_time": (
            "ALTER TABLE mediations ADD COLUMN mediation_time VARCHAR(20) NULL"
        ),
        "location": (
            "ALTER TABLE mediations ADD COLUMN location VARCHAR(200) NULL"
        ),
        "summary_notes": (
            "ALTER TABLE mediations ADD COLUMN summary_notes TEXT NULL"
        ),
        "resolution_status": (
            "ALTER TABLE mediations "
            "ADD COLUMN resolution_status VARCHAR(30) DEFAULT 'scheduled'"
        ),
        "next_hearing_date": (
            "ALTER TABLE mediations ADD COLUMN next_hearing_date DATE NULL"
        ),
        "agreement_document_path": (
            "ALTER TABLE mediations "
            "ADD COLUMN agreement_document_path VARCHAR(500) NULL"
        ),
        "mediator_name": (
            "ALTER TABLE mediations ADD COLUMN mediator_name VARCHAR(200) NULL"
        ),
        "resolution_photo_path": (
            "ALTER TABLE mediations "
            "ADD COLUMN resolution_photo_path VARCHAR(500) NULL"
        ),
        "updated_at": (
            "ALTER TABLE mediations "
            "ADD COLUMN updated_at DATETIME "
            "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
        ),
    },
    "cases": {
        "status": (
            "ALTER TABLE cases "
            "ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending'"
        ),
        "updated_at": (
            "ALTER TABLE cases "
            "ADD COLUMN updated_at DATETIME "
            "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
        ),
        "category": (
            "ALTER TABLE cases ADD COLUMN category VARCHAR(50) NULL"
        ),
        "urgency": (
            "ALTER TABLE cases ADD COLUMN urgency VARCHAR(20) DEFAULT 'medium'"
        ),
        "is_cross_barangay": (
            "ALTER TABLE cases ADD COLUMN is_cross_barangay BOOLEAN DEFAULT FALSE"
        ),
        "complaint_barangay_id": (
            "ALTER TABLE cases ADD COLUMN complaint_barangay_id INT NULL"
        ),
    },
    "users": {
        "id_photo_url": (
            "ALTER TABLE users ADD COLUMN id_photo_url VARCHAR(500) NULL"
        ),
        "selfie_with_id_path": (
            "ALTER TABLE users ADD COLUMN selfie_with_id_path VARCHAR(500) NULL"
        ),
        "profile_photo_path": (
            "ALTER TABLE users ADD COLUMN profile_photo_path VARCHAR(500) NULL"
        ),
        "verification_status": (
            "ALTER TABLE users "
            "ADD COLUMN verification_status VARCHAR(20) DEFAULT 'pending'"
        ),
        "verification_method": (
            "ALTER TABLE users ADD COLUMN verification_method VARCHAR(50) NULL"
        ),
        "email_verified": (
            "ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE"
        ),
        "mobile_verified": (
            "ALTER TABLE users ADD COLUMN mobile_verified BOOLEAN DEFAULT FALSE"
        ),
        "approved_by": (
            "ALTER TABLE users ADD COLUMN approved_by INT NULL"
        ),
        "approved_at": (
            "ALTER TABLE users ADD COLUMN approved_at DATETIME NULL"
        ),
        "house_number": (
            "ALTER TABLE users ADD COLUMN house_number VARCHAR(50) NULL"
        ),
        "street_name": (
            "ALTER TABLE users ADD COLUMN street_name VARCHAR(100) NULL"
        ),
        "purok": (
            "ALTER TABLE users ADD COLUMN purok VARCHAR(50) NULL"
        ),
        "city": (
            "ALTER TABLE users ADD COLUMN city VARCHAR(100) NULL"
        ),
        "province": (
            "ALTER TABLE users ADD COLUMN province VARCHAR(100) NULL"
        ),
        "zip_code": (
            "ALTER TABLE users ADD COLUMN zip_code VARCHAR(10) NULL"
        ),
        "rejected_by": (
            "ALTER TABLE users ADD COLUMN rejected_by INT NULL"
        ),
        "rejected_at": (
            "ALTER TABLE users ADD COLUMN rejected_at DATETIME NULL"
        ),
        "rejection_reason": (
            "ALTER TABLE users ADD COLUMN rejection_reason VARCHAR(500) NULL"
        ),
        "otp_code": (
            "ALTER TABLE users ADD COLUMN otp_code VARCHAR(255) NULL"
        ),
        "otp_expiry": (
            "ALTER TABLE users ADD COLUMN otp_expiry DATETIME NULL"
        ),
        "otp_attempts": (
            "ALTER TABLE users ADD COLUMN otp_attempts INT DEFAULT 0"
        ),
    },
    "requests": {
        "file_url": (
            "ALTER TABLE requests ADD COLUMN file_url VARCHAR(500) NULL"
        ),
        "updated_at": (
            "ALTER TABLE requests "
            "ADD COLUMN updated_at DATETIME "
            "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
        ),
    },
}

# ---------------------------------------------------------------------------
# Stale columns to remove: {table: [column, ...]}
# These were created by previous migrations and are no longer used.
# ---------------------------------------------------------------------------
STALE_COLUMNS: dict[str, list[str]] = {
    "mediations": ["complaint_id"],
}

# ---------------------------------------------------------------------------
# Nullable fixes: columns that must be nullable but may have been created
# as NOT NULL by an older schema. MODIFY COLUMN is idempotent on MySQL.
# ---------------------------------------------------------------------------
NULLABLE_FIXES: dict[str, dict[str, str]] = {
    "mediations": {
        "mediation_time": (
            "ALTER TABLE mediations "
            "MODIFY COLUMN mediation_time VARCHAR(20) NULL"
        ),
        "location": (
            "ALTER TABLE mediations "
            "MODIFY COLUMN location VARCHAR(200) NULL"
        ),
        "summary_notes": (
            "ALTER TABLE mediations "
            "MODIFY COLUMN summary_notes TEXT NULL"
        ),
        "mediator_name": (
            "ALTER TABLE mediations "
            "MODIFY COLUMN mediator_name VARCHAR(200) NULL"
        ),
    },
}


def _drop_stale_columns(table: str, existing: set) -> None:
    """Drop columns that are no longer referenced by the application."""
    stale = STALE_COLUMNS.get(table, [])
    for col in stale:
        if col not in existing:
            continue
        try:
            with engine.begin() as conn:
                conn.execute(text(f"ALTER TABLE {table} DROP COLUMN {col}"))
            logger.info(f"Schema guard: dropped stale column '{col}' from '{table}'.")
        except Exception as exc:
            logger.warning(
                f"Schema guard: could not drop '{col}' from '{table}': {exc}"
            )


def _fix_nullable_columns(table: str, existing: set) -> None:
    """Ensure columns that must be nullable are not NOT NULL in the DB."""
    fixes = NULLABLE_FIXES.get(table, {})
    for col, ddl in fixes.items():
        if col not in existing:
            continue
        try:
            with engine.begin() as conn:
                conn.execute(text(ddl))
            logger.info(
                f"Schema guard: ensured '{col}' in '{table}' is nullable."
            )
        except Exception as exc:
            logger.warning(
                f"Schema guard: nullable fix for '{col}' in '{table}' failed: {exc}"
            )


def validate_schema() -> None:
    """
    Inspect the live database and repair schema drift.

    Order of operations per table:
      1. Drop stale columns (e.g. complaint_id left by old migration)
      2. Add missing required columns
      3. Fix NOT NULL columns that should be nullable
    """
    try:
        inspector = inspect(engine)
        live_tables = set(inspector.get_table_names())
    except Exception as exc:
        logger.error(f"Schema guard: cannot inspect DB — {exc}")
        return

    all_tables = set(REQUIRED_COLUMNS) | set(STALE_COLUMNS) | set(NULLABLE_FIXES)

    for table in all_tables:
        if table not in live_tables:
            logger.warning(
                f"Schema guard: table '{table}' does not exist yet — skipped."
            )
            continue

        try:
            existing = {c["name"] for c in inspector.get_columns(table)}
        except Exception as exc:
            logger.warning(
                f"Schema guard: cannot read columns for '{table}': {exc}"
            )
            continue

        # Step 1 — remove stale columns
        _drop_stale_columns(table, existing)

        # Refresh existing set after potential drops
        try:
            existing = {c["name"] for c in inspector.get_columns(table)}
        except Exception:
            pass

        # Step 2 — add missing required columns
        for col, ddl in REQUIRED_COLUMNS.get(table, {}).items():
            if col in existing:
                continue
            try:
                with engine.begin() as conn:
                    conn.execute(text(ddl))
                logger.info(
                    f"Schema guard: added missing column '{col}' to '{table}'."
                )
            except Exception as exc:
                logger.warning(
                    f"Schema guard: could not add '{col}' to '{table}': {exc}"
                )

        # Step 3 — fix NOT NULL columns that must be nullable
        _fix_nullable_columns(table, existing)
