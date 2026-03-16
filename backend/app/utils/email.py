"""Email sending utilities.

Provider priority (first configured one wins):
  1. SendGrid  — set SENDGRID_API_KEY + SENDGRID_FROM_EMAIL
                 Easy: single-sender verification (verify any Gmail, no domain needed)
                 Free: 100 emails/day
                 Sign up: sendgrid.com

  2. Resend    — set RESEND_API_KEY + RESEND_FROM_EMAIL
                 Requires domain verification in Resend dashboard
                 Free: 3 000 emails/month
                 Sign up: resend.com

  3. SMTP      — set SMTP_HOST + SMTP_PORT + SMTP_USERNAME + SMTP_PASSWORD + SMTP_FROM_EMAIL
                 ⚠ Railway free/hobby blocks outbound SMTP (ports 25/465/587).
                 Only use this for non-Railway deployments.

Railway fix: use SendGrid (easiest) or Resend (requires domain).
"""
import re
import smtplib
import ssl
import logging
import requests
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from ..core.config import settings

logger = logging.getLogger(__name__)

_EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")


def _valid_email(addr: str | None) -> str | None:
    """Return addr if it contains a valid email, else None."""
    if not addr:
        return None
    addr = addr.strip()
    if _EMAIL_RE.search(addr):
        return addr
    return None


# ── 1. SendGrid ────────────────────────────────────────────────────────────────

def _send_via_sendgrid(to_email: str, subject: str, body_html: str) -> bool:
    from_addr = _valid_email(settings.sendgrid_from_email)
    if not from_addr:
        logger.error(
            "[EMAIL/SendGrid] SENDGRID_FROM_EMAIL is not set or invalid. "
            "Set it to your SendGrid-verified email address."
        )
        return False

    try:
        resp = requests.post(
            "https://api.sendgrid.com/v3/mail/send",
            headers={
                "Authorization": f"Bearer {settings.sendgrid_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "personalizations": [{"to": [{"email": to_email}]}],
                "from": {"email": from_addr},
                "subject": subject,
                "content": [{"type": "text/html", "value": body_html}],
            },
            timeout=15,
        )
        # SendGrid returns 202 Accepted on success
        if resp.status_code == 202:
            logger.info("[EMAIL/SendGrid] Sent '%s' to %s", subject, to_email)
            return True
        try:
            err = resp.json()
        except Exception:
            err = resp.text
        logger.error(
            "[EMAIL/SendGrid] Failed '%s' to %s: HTTP %s — %s",
            subject, to_email, resp.status_code, err,
        )
        return False
    except Exception as exc:
        logger.error("[EMAIL/SendGrid] Exception: %s", exc)
        return False


# ── 2. Resend ──────────────────────────────────────────────────────────────────

def _send_via_resend(to_email: str, subject: str, body_html: str) -> bool:
    # Use RESEND_FROM_EMAIL (dedicated setting); do NOT fall back to smtp_from_email
    # because that may be an unverified address or in the wrong format.
    from_addr = _valid_email(settings.resend_from_email)
    if not from_addr:
        logger.error(
            "[EMAIL/Resend] RESEND_FROM_EMAIL is not set or invalid. "
            "Set it to an email on your Resend-verified domain, e.g. noreply@yourdomain.com. "
            "Note: onboarding@resend.dev only delivers to your own Resend account email."
        )
        return False

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
        try:
            err = resp.json()
        except Exception:
            err = resp.text
        logger.error(
            "[EMAIL/Resend] Failed '%s' to %s: HTTP %s — %s",
            subject, to_email, resp.status_code, err,
        )
        return False
    except Exception as exc:
        logger.error("[EMAIL/Resend] Exception: %s", exc)
        return False


# ── 3. SMTP ────────────────────────────────────────────────────────────────────

def _send_via_smtp(to_email: str, subject: str, body_html: str) -> bool:
    if not all([settings.smtp_host, settings.smtp_username,
                settings.smtp_password, settings.smtp_from_email]):
        logger.warning(
            "[EMAIL/SMTP] Not fully configured — missing one of: "
            "SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM_EMAIL."
        )
        return False

    from_addr = _valid_email(settings.smtp_from_email)
    if not from_addr:
        logger.error("[EMAIL/SMTP] SMTP_FROM_EMAIL is not a valid email address.")
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = from_addr
    msg["To"]      = to_email
    msg.attach(MIMEText(body_html, "html"))

    ctx = ssl.create_default_context()
    try:
        if settings.smtp_use_ssl:
            with smtplib.SMTP_SSL(
                settings.smtp_host, settings.smtp_port, context=ctx, timeout=10
            ) as srv:
                srv.login(settings.smtp_username, settings.smtp_password)
                srv.sendmail(from_addr, to_email, msg.as_string())
        else:
            with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as srv:
                srv.ehlo()
                srv.starttls(context=ctx)
                srv.login(settings.smtp_username, settings.smtp_password)
                srv.sendmail(from_addr, to_email, msg.as_string())
        logger.info("[EMAIL/SMTP] Sent '%s' to %s", subject, to_email)
        return True
    except Exception as exc:
        logger.error(
            "[EMAIL/SMTP] Failed '%s' to %s: %s — "
            "Railway blocks outbound SMTP. Use SendGrid or Resend instead.",
            subject, to_email, exc,
        )
        return False


# ── Dispatcher ─────────────────────────────────────────────────────────────────

def _send_email(to_email: str, subject: str, body_html: str) -> bool:
    """Try each configured provider in order. Returns True if sent."""
    if settings.sendgrid_api_key:
        return _send_via_sendgrid(to_email, subject, body_html)
    if settings.resend_api_key:
        return _send_via_resend(to_email, subject, body_html)
    return _send_via_smtp(to_email, subject, body_html)


# ── Templates ──────────────────────────────────────────────────────────────────

def send_otp_email(to_email: str, otp: str) -> bool:
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
