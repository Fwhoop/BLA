"""Philippine phone number normalization utilities."""
import re


def normalize_ph_phone(phone: str) -> str:
    """Normalize a Philippine phone number to E.164 format (+63XXXXXXXXX).

    Accepts:
      09559952920   → +639559952920
      9559952920    → +639559952920
      639559952920  → +639559952920
      +639559952920 → +639559952920  (unchanged)
    """
    if not phone:
        return phone

    # Strip spaces, dashes, parens
    phone = re.sub(r"[\s\-\(\)]", "", phone.strip())

    if phone.startswith("+63"):
        return phone                          # already E.164
    if phone.startswith("63") and len(phone) >= 11:
        return "+" + phone                    # missing leading +
    if phone.startswith("0") and len(phone) == 11:
        return "+63" + phone[1:]              # 09XX… → +639XX…
    if not phone.startswith("0") and len(phone) == 10:
        return "+63" + phone                  # 9XX… → +639XX…

    return phone  # return as-is if we can't recognise the format
