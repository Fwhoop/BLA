from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "sqlite:///./fallback.db"
    jwt_secret: str = "change-me-in-production"
    port: int = 8000
    debug: bool = True

    mysql_root_password: str | None = None
    mysql_database: str | None = None
    mysql_user: str | None = None
    mysql_password: str | None = None

    hf_token: str | None = None

    # Firebase Admin SDK (JSON string of service account credentials)
    firebase_credentials_json: str | None = None

    # ── Resend API (recommended on Railway — SMTP ports are blocked) ──────────
    # Sign up free at resend.com → create API key → set this env var.
    # From address: set SMTP_FROM_EMAIL to e.g. "BLA <noreply@yourdomain.com>"
    resend_api_key: str | None = None

    # ── SMTP (fallback — only works if your host allows outbound port 587/465) ─
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_use_ssl: bool = False   # True → SMTP_SSL (port 465); False → STARTTLS (port 587)
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from_email: str | None = None

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
