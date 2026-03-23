"""
Database readiness guard.

Blocks startup until the DB accepts connections. Prevents crashes when
Railway starts the DB container after the API container.
"""

import time
import logging
from sqlalchemy import text
from app.db import engine

logger = logging.getLogger(__name__)


def wait_for_database(max_retries: int = 30, delay: float = 2.0) -> bool:
    """
    Attempt a SELECT 1 probe on the configured database.

    Retries up to *max_retries* times with *delay* seconds between each
    attempt. Returns True when the database is ready, False if all retries
    are exhausted (the caller decides whether to abort or continue).
    """
    for attempt in range(1, max_retries + 1):
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            logger.info(f"Database ready after {attempt} attempt(s).")
            return True
        except Exception as exc:
            logger.warning(
                f"DB not ready (attempt {attempt}/{max_retries}): {exc}"
            )
            if attempt < max_retries:
                time.sleep(delay)

    logger.error(
        "Database never became ready after %d attempts — proceeding anyway.",
        max_retries,
    )
    return False
