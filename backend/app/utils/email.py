"""Email sending utilities using smtplib (built-in)."""
import smtplib
import ssl
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from ..core.config import settings

logger = logging.getLogger(__name__)


def _send_email(to_email: str, subject: str, body_html: str) -> None:
    """Internal helper — sends an HTML email via SMTP."""
    if not all([settings.smtp_host, settings.smtp_username, settings.smtp_password, settings.smtp_from_email]):
        logger.warning("[EMAIL] SMTP not configured — skipping email send to %s", to_email)
        return

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from_email
    msg["To"] = to_email
    msg.attach(MIMEText(body_html, "html"))

    context = ssl.create_default_context()
    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
            server.ehlo()
            server.starttls(context=context)
            server.login(settings.smtp_username, settings.smtp_password)
            server.sendmail(settings.smtp_from_email, to_email, msg.as_string())
        logger.info("[EMAIL] Sent '%s' to %s", subject, to_email)
    except Exception as e:
        logger.warning("[EMAIL] Failed to send to %s: %s", to_email, e)


def send_otp_email(to_email: str, otp: str) -> None:
    """Send a 6-digit OTP for signup/email verification."""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Verification Code</h2>
      <p>Your verification code is:</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#99272D;padding:16px 0;">{otp}</div>
      <p style="color:#555;">This code expires in <strong>5 minutes</strong>.</p>
      <p style="color:#888;font-size:12px;">If you did not request this, please ignore this email.</p>
    </div>
    """
    _send_email(to_email, "BLA Verification Code", body)


def send_password_reset_email(to_email: str, otp: str) -> None:
    """Send a 6-digit OTP for password reset."""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Password Reset</h2>
      <p>Your password reset code is:</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#99272D;padding:16px 0;">{otp}</div>
      <p style="color:#555;">This code expires in <strong>5 minutes</strong>.</p>
      <p style="color:#888;font-size:12px;">If you did not request a password reset, please ignore this email.</p>
    </div>
    """
    _send_email(to_email, "BLA Password Reset Code", body)


def send_admin_approved_email(to_email: str, name: str) -> None:
    """Notify an admin that their account has been approved."""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Account Approved</h2>
      <p>Hello <strong>{name}</strong>,</p>
      <p>Your admin account has been <strong style="color:green;">approved</strong> by the Super Administrator.</p>
      <p>You can now log in to access your barangay dashboard.</p>
    </div>
    """
    _send_email(to_email, "BLA Admin Account Approved", body)


def send_admin_rejected_email(to_email: str, name: str, reason: str = "") -> None:
    """Notify an admin that their registration was rejected."""
    reason_html = f"<p><strong>Reason:</strong> {reason}</p>" if reason else ""
    body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e0e0e0;border-radius:8px;">
      <h2 style="color:#99272D;">Barangay Legal Aid — Registration Update</h2>
      <p>Hello <strong>{name}</strong>,</p>
      <p>Your admin registration has been <strong style="color:#B3261E;">rejected</strong>.</p>
      {reason_html}
      <p style="color:#888;font-size:12px;">If you believe this is an error, please contact your barangay office.</p>
    </div>
    """
    _send_email(to_email, "BLA Admin Registration Update", body)
