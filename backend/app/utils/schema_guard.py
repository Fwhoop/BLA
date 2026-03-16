"""
Schema drift protection.

On every startup, inspects the live database tables and compares them
against the required column definitions. Any missing column is added
automatically via ALTER TABLE, isolated in its own transaction so one
failure cannot block the others.

This prevents Railway deployments from crashing due to a schema that
was created by an older version of the model.

Special case handled: the `mediations` table may have been created when
the FK column was named `case_id`. If `complaint_id` is absent but
`case_id` is present, data is copied and the canonical column is created.
"""

import logging
from sqlalchemy import inspect, text
from app.db import engine

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Required columns: {table: {column: ALTER TABLE DDL}}
# Every column the application ever reads or writes must appear here.
# ---------------------------------------------------------------------------
REQUIRED_COLUMNS: dict[str, dict[str, str]] = {
    "mediations": {
        # Primary FK — this is the column that causes the 500 crash
        "complaint_id": (
            "ALTER TABLE mediations "
            "ADD COLUMN complaint_id INT NULL"
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


def _handle_mediations_complaint_id(
    existing_cols: set, inspector_ref
) -> None:
    """
    Special repair for the mediations.complaint_id column.

    History: the table was created when the FK was named `case_id`.
    The model was later renamed to `complaint_id`, but `create_all()`
    skips existing tables — so the column never appeared in the live DB.

    Strategy:
      1. If `complaint_id` already exists → nothing to do.
      2. If `case_id` exists but `complaint_id` does not → add
         `complaint_id` as a nullable INT, backfill from `case_id`.
      3. If neither exists → add `complaint_id` as a plain nullable INT.
    """
    if "complaint_id" in existing_cols:
        return  # already correct

    try:
        if "case_id" in existing_cols:
            # Backfill path: copy existing FK data into the new column name
            with engine.begin() as conn:
                conn.execute(
                    text(
                        "ALTER TABLE mediations "
                        "ADD COLUMN complaint_id INT NULL"
                    )
                )
                conn.execute(
                    text("UPDATE mediations SET complaint_id = case_id")
                )
            logger.info(
                "Schema guard: added mediations.complaint_id "
                "and backfilled from case_id."
            )
        else:
            with engine.begin() as conn:
                conn.execute(
                    text(
                        "ALTER TABLE mediations "
                        "ADD COLUMN complaint_id INT NULL"
                    )
                )
            logger.info(
                "Schema guard: added mediations.complaint_id (no case_id found)."
            )
    except Exception as exc:
        logger.warning(
            f"Schema guard: mediations.complaint_id repair failed: {exc}"
        )


def validate_schema() -> None:
    """
    Inspect the live database and add any missing columns.

    Each table is repaired inside its own independent transaction so a
    failure on one table cannot prevent repairs on others.
    """
    try:
        inspector = inspect(engine)
        live_tables = set(inspector.get_table_names())
    except Exception as exc:
        logger.error(f"Schema guard: cannot inspect DB — {exc}")
        return

    for table, columns in REQUIRED_COLUMNS.items():
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

        # Special case: mediations FK rename
        if table == "mediations":
            _handle_mediations_complaint_id(existing, inspector)
            # Re-read after potential repair so the loop below doesn't try again
            try:
                existing = {c["name"] for c in inspector.get_columns(table)}
            except Exception:
                pass

        for col, ddl in columns.items():
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
