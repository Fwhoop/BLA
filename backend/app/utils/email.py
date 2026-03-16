"""Email sending utilities.

Primary: Resend HTTP API (https://resend.com) — works on Railway (port 443).
Fallback: smtplib — only works if the host allows outbound SMTP (ports 587/465).

Railway free/hobby plans block all outbound SMTP TCP connections.
Set RESEND_API_KEY in your Railway environment variables to fix this.
"""
import smtplib
import ssl
import logging
import requests
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from ..core.config import settings

logger = logging.getLogger(__name__)


# ── Resend HTTP API ────────────────────────────────────────────────────────────

def _send_via_resend(to_email: str, subject: str, body_html: str) -> bool:
    """Send email via Resend REST API (HTTPS — works on Railway).

    Requires RESEND_API_KEY env var.
    From address uses SMTP_FROM_EMAIL if set, otherwise falls back to
    the Resend shared test address (only delivers to the Resend account owner).
    """
    from_addr = settings.smtp_from_email or "Barangay Legal Aid <onboarding@resend.dev>"
    try:
        resp = requests.post(
            "https://api.resend.com/emails",
            headers={
                "Authorization": f"Bearer {settings.resend_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "from": from_addr,
                "to": [to_email],
                "subject": subject,
                "html": body_html,
            },
            timeout=15,
        )
        if resp.status_code in (200, 201):
            logger.info("[EMAIL/Resend] Sent '%s' to %s", subject, to_email)
            return True
        # Resend returns structured errors
        try:
            err = resp.json()
        except Exception:
            err = resp.text
        logger.error(
            "[EMAIL/Resend] Failed to send '%s' to %s: HTTP %s — %s",
            subject, to_email, resp.status_code, err,
        )
        return False
    except Exception as exc:
        logger.error("[EMAIL/Resend] Exception sending '%s' to %s: %s", subject, to_email, exc)
        return False


# ── SMTP fallback ──────────────────────────────────────────────────────────────

def _send_via_smtp(to_email: str, subject: str, body_html: str) -> bool:
    """Send email via SMTP (STARTTLS port 587 or SSL port 465).

    NOTE: Railway free/hobby plans block outbound SMTP.
          Use Resend (HTTP API) instead — set RESEND_API_KEY.
    """
    if not all([settings.smtp_host, settings.smtp_username,
                settings.smtp_password, settings.smtp_from_email]):
        logger.warning(
            "[EMAIL/SMTP] Not configured — missing SMTP_HOST / SMTP_USERNAME / "
            "SMTP_PASSWORD / SMTP_FROM_EMAIL. Skipping send to %s.", to_email,
        )
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = settings.smtp_from_email
    msg["To"]      = to_email
    msg.attach(MIMEText(body_html, "html"))

    ctx = ssl.create_default_context()
    try:
        if settings.smtp_use_ssl:
            with smtplib.SMTP_SSL(
                settings.smtp_host, settings.smtp_port, context=ctx, timeout=10
            ) as srv:
                srv.login(settings.smtp_username, settings.smtp_password)
                srv.sendmail(settings.smtp_from_email, to_email, msg.as_string())
        else:
            with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as srv:
                srv.ehlo()
                srv.starttls(context=ctx)
                srv.login(settings.smtp_username, settings.smtp_password)
                srv.sendmail(settings.smtp_from_email, to_email, msg.as_string())
        logger.info("[EMAIL/SMTP] Sent '%s' to %s", subject, to_email)
        return True
    except Exception as exc:
        logger.error(
            "[EMAIL/SMTP] Failed to send '%s' to %s: %s. "
            "Railway blocks SMTP — switch to Resend: set RESEND_API_KEY env var.",
            subject, to_email, exc,
        )
        return False


# ── Public dispatcher ──────────────────────────────────────────────────────────

def _send_email(to_email: str, subject: str, body_html: str) -> bool:
    """Send an HTML email. Returns True if delivered, False otherwise.

    Tries Resend first (works on Railway), then falls back to SMTP.
    """
    if settings.resend_api_key:
        return _send_via_resend(to_email, subject, body_html)
    return _send_via_smtp(to_email, subject, body_html)


# ── Email templates ───────────────────────────────────────────────────────────

def send_otp_email(to_email: str, otp: str) -> bool:
    """Send a 6-digit OTP for signup/email verification. Returns True if sent."""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;
                border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Verification Code</h2>
      <p>Your verification code is:</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#99272D;
                  padding:16px 0;">{otp}</div>
      <p style="color:#555;">This code expires in <strong>5 minutes</strong>.</p>
      <p style="color:#888;font-size:12px;">If you did not request this, please ignore this email.</p>
    </div>
    """
    return _send_email(to_email, "BLA Verification Code", body)


def send_password_reset_email(to_email: str, otp: str) -> bool:
    """Send a 6-digit OTP for password reset. Returns True if sent."""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;
                border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Password Reset</h2>
      <p>Your password reset code is:</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#99272D;
                  padding:16px 0;">{otp}</div>
      <p style="color:#555;">This code expires in <strong>5 minutes</strong>.</p>
      <p style="color:#888;font-size:12px;">If you did not request a password reset,
         please ignore this email.</p>
    </div>
    """
    return _send_email(to_email, "BLA Password Reset Code", body)


def send_admin_approved_email(to_email: str, name: str) -> None:
    """Notify an admin that their account has been approved."""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;
                border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Account Approved</h2>
      <p>Hello <strong>{name}</strong>,</p>
      <p>Your admin account has been <strong style="color:green;">approved</strong>
         by the Super Administrator.</p>
      <p>You can now log in to access your barangay dashboard.</p>
    </div>
    """
    _send_email(to_email, "BLA Admin Account Approved", body)


def send_admin_rejected_email(to_email: str, name: str, reason: str = "") -> None:
    """Notify an admin that their registration was rejected."""
    reason_html = f"<p><strong>Reason:</strong> {reason}</p>" if reason else ""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;
                border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Registration Update</h2>
      <p>Hello <strong>{name}</strong>,</p>
      <p>Your admin registration has been
         <strong style="color:#B3261E;">rejected</strong>.</p>
      {reason_html}
      <p style="color:#888;font-size:12px;">If you believe this is an error,
         please contact your barangay office.</p>
    </div>
    """
    _send_email(to_email, "BLA Admin Registration Update", body)
