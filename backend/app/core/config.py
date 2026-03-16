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

    # ── Resend API ────────────────────────────────────────────────────────────
    # Railway blocks SMTP — use Resend HTTP API instead (port 443, never blocked).
    # 1. Sign up free at resend.com
    # 2. Add & verify a domain (or use a free domain)  ← required to send to anyone
    # 3. Create an API key → paste below
    # 4. Set RESEND_FROM_EMAIL to "BLA <noreply@yourdomain.com>"
    resend_api_key: str | None = None
    resend_from_email: str | None = None   # e.g. "BLA <noreply@yourdomain.com>"

    # ── SendGrid API (alternative — supports single-sender verification) ───────
    # Easier than Resend if you don't own a domain:
    # 1. Sign up free at sendgrid.com (100 emails/day free)
    # 2. Settings → Sender Authentication → Single Sender Verification → verify your Gmail
    # 3. Settings → API Keys → Create API Key (Full Access)
    # 4. Set SENDGRID_API_KEY and SENDGRID_FROM_EMAIL (your verified Gmail)
    sendgrid_api_key: str | None = None
    sendgrid_from_email: str | None = None  # must be your SendGrid-verified email

    # ── SMTP (last resort — Railway blocks ports 25/465/587) ──────────────────
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_use_ssl: bool = False
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from_email: str | None = None

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
