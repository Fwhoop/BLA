"""
chatbot.py — BLA FAQ search and fallback engine.

Provides:
  - load_faq_data()        — load barangay_law_flutter.json
  - chat_response(sender, message) -> dict  — legal topic answers + FAQ search + fallback
"""

import os
import re
import json
import logging
from typing import Optional

logger = logging.getLogger(__name__)

_BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
_JSON_FILE = os.path.join(os.path.dirname(_BASE_DIR), "barangay_law_flutter.json")

logger.info(f"[STARTUP] FAQ JSON path → {_JSON_FILE}")

# ── FAQ / knowledge base ──────────────────────────────────────────────────────
_faq_cache: Optional[dict] = None


def load_faq_data() -> Optional[dict]:
    global _faq_cache
    if _faq_cache is not None:
        return _faq_cache
    if not os.path.exists(_JSON_FILE):
        logger.warning(f"FAQ file not found: {_JSON_FILE}")
        return None
    try:
        with open(_JSON_FILE, "r", encoding="utf-8") as f:
            _faq_cache = json.load(f)
        logger.info(f"[STARTUP] FAQ loaded — {len(_faq_cache.get('categories', []))} categories")
    except Exception as e:
        logger.error(f"FAQ load error: {e}")
    return _faq_cache


_STOP_WORDS = {
    "a", "an", "the", "is", "it", "in", "on", "at", "to", "for", "of", "and",
    "or", "but", "how", "do", "i", "my", "me", "you", "we", "can", "what",
    "when", "where", "who", "which", "are", "was", "be", "been", "being",
    "have", "has", "had", "will", "would", "could", "should", "may", "might",
    "this", "that", "these", "those", "get", "give", "make", "go", "want",
    "need", "please", "tell", "about", "with", "from", "by",
}


def _keywords(text: str) -> set:
    words = re.sub(r"[^\w\s]", "", text.lower()).split()
    return {w for w in words if w not in _STOP_WORDS and len(w) > 2}


# ── Built-in structured legal topic answers ───────────────────────────────────
# Each entry: list of trigger keywords → structured answer
# A query matches if it shares ≥2 trigger keywords (or 1 strong unique keyword)

_LEGAL_TOPICS = [
    {
        "triggers": {"summon", "summoning", "summons", "mediation", "katarungang", "pambarangay", "lupon", "lupong", "tagapamayapa", "kp"},
        "answer": (
            "**Summoning Rules in Barangay Mediation (KP Process)**\n\n"
            "Here is the step-by-step process:\n\n"
            "**Step 1 — File a complaint**\n"
            "The complainant files a written or verbal complaint at the Barangay Hall. "
            "The Barangay Captain or Lupon Secretary receives it.\n\n"
            "**Step 2 — Issue a summons**\n"
            "The Punong Barangay issues a written summons to the respondent within **2 days** "
            "of receiving the complaint. The summons must state the complaint and the date/time of mediation.\n\n"
            "**Step 3 — Respondent must appear**\n"
            "The respondent is required by law to appear on the set date. "
            "Failure to appear without valid reason is a ground for the complainant to certify "
            "the dispute for court action.\n\n"
            "**Step 4 — Mediation proper**\n"
            "The Punong Barangay mediates. Both parties present their side. "
            "The goal is an amicable settlement within **15 days** (extendable to 30 days).\n\n"
            "**Step 5 — If no settlement**\n"
            "The dispute is referred to the Pangkat ng Tagapagkasundo (conciliation panel) "
            "for another 15 days of conciliation.\n\n"
            "**Step 6 — Certificate to File Action**\n"
            "If still unresolved, a Certificate to File Action (CFA) is issued, "
            "allowing the parties to bring the case to court.\n\n"
            "📋 **Legal Basis:** RA 7160 (Local Government Code), Sections 399–422 — "
            "Katarungang Pambarangay Law"
        ),
    },
    {
        "triggers": {"debt", "utang", "bayad", "bayaran", "owe", "owes", "refuses", "pay", "collection", "borrow", "borrowed", "lending", "loan"},
        "answer": (
            "**Neighbour Refuses to Pay Debt — What You Can Do**\n\n"
            "Here is the step-by-step process:\n\n"
            "**Step 1 — Send a demand**\n"
            "First, send a written demand letter asking your neighbour to pay. "
            "Keep a copy. Give them a reasonable deadline (7–15 days).\n\n"
            "**Step 2 — File at the Barangay**\n"
            "If they ignore the demand, go to your Barangay Hall and file a complaint. "
            "Bring proof of the debt (written agreement, receipts, messages, witnesses).\n\n"
            "**Step 3 — Barangay mediation**\n"
            "The Punong Barangay will summon your neighbour for mediation. "
            "Both sides present their case. The barangay will try to reach an amicable settlement.\n\n"
            "**Step 4 — Amicable settlement**\n"
            "If your neighbour agrees to pay, a written settlement is signed before the barangay. "
            "This has the force of a final court judgment and is enforceable.\n\n"
            "**Step 5 — Certificate to File Action**\n"
            "If your neighbour refuses mediation or fails to comply with the settlement, "
            "the barangay issues a Certificate to File Action (CFA). "
            "You can then file a case in the Municipal Trial Court.\n\n"
            "💡 **Note:** For debts ≤ ₱400,000, you may file a Small Claims case in court — "
            "no lawyer needed, quick resolution.\n\n"
            "📋 **Legal Basis:** RA 7160, Sections 399–422 (KP Law); "
            "Rule of Procedure for Small Claims Cases (A.M. No. 08-8-7-SC, as amended)"
        ),
    },
    {
        "triggers": {"clearance", "barangay clearance", "certificate", "residency"},
        "answer": (
            "**How to Get a Barangay Clearance**\n\n"
            "Here is the step-by-step process:\n\n"
            "**Step 1 — Go to the Barangay Hall**\n"
            "Visit your local Barangay Hall during office hours (usually 8AM–5PM, Monday–Friday).\n\n"
            "**Step 2 — Bring the requirements**\n"
            "- Valid government-issued ID\n"
            "- Proof of residency (utility bill, lease contract, or declaration from a neighbor)\n"
            "- Cedula (Community Tax Certificate) — available at the same barangay or City Hall\n\n"
            "**Step 3 — Fill out the form**\n"
            "Request and fill out the Barangay Clearance application form at the counter.\n\n"
            "**Step 4 — Pay the fee**\n"
            "Pay the processing fee (typically ₱50–₱200, varies per barangay).\n\n"
            "**Step 5 — Receive your clearance**\n"
            "The clearance is usually released on the same day or within 1–3 working days. "
            "It is valid for 6 months to 1 year depending on the barangay.\n\n"
            "📋 **Legal Basis:** RA 7160 (Local Government Code), Section 389 — "
            "Powers and Duties of the Punong Barangay"
        ),
    },
    {
        "triggers": {"noise", "disturbance", "videoke", "karaoke", "loud", "curfew", "ordinance", "nuisance"},
        "answer": (
            "**Noise Disturbance and Curfew Violations**\n\n"
            "Here is how the barangay handles these:\n\n"
            "**Step 1 — Talk to the person first**\n"
            "If safe to do so, politely inform your neighbor about the disturbance.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "Go to the Barangay Hall or contact the Barangay Tanod/Captain to report the disturbance. "
            "Barangay tanods can respond to noise complaints within the barangay.\n\n"
            "**Step 3 — Barangay ordinance enforcement**\n"
            "Most barangays prohibit loud music or videoke past 10PM under their local ordinances. "
            "Violations are subject to fines or confiscation of equipment.\n\n"
            "**Step 4 — File a formal complaint**\n"
            "If the disturbance continues, file a formal complaint at the Barangay Hall. "
            "The Lupon will summon the respondent for mediation.\n\n"
            "**Step 5 — Repeat violations**\n"
            "Habitual violators may be referred to the Municipal/City for stronger sanctions.\n\n"
            "📋 **Legal Basis:** RA 7160, Section 389(b) — Barangay ordinance enforcement; "
            "Local Anti-Noise Ordinances; RA 7586 (environmental nuisance provisions)"
        ),
    },
    {
        "triggers": {"vawc", "violence", "abuse", "domestic", "battered", "rape", "harassment", "stalking", "women", "children"},
        "answer": (
            "**Violence Against Women and Children (VAWC)**\n\n"
            "Here is what to do:\n\n"
            "**Step 1 — Seek safety first**\n"
            "If you are in immediate danger, call the police (911) or go to the nearest barangay. "
            "Barangay tanods can escort you to safety.\n\n"
            "**Step 2 — Go to the Barangay Hall**\n"
            "Report to the Barangay VAWC Desk. Every barangay is required to have a VAWC Desk Officer.\n\n"
            "**Step 3 — Get a Barangay Protection Order (BPO)**\n"
            "The Punong Barangay can issue a Barangay Protection Order (BPO) within the same day. "
            "This legally prohibits the abuser from threatening, harassing, or contacting you.\n\n"
            "**Step 4 — File a police report**\n"
            "Go to the nearest PNP station and file a formal complaint. "
            "Request a medico-legal certificate if you have injuries.\n\n"
            "**Step 5 — File a case in court**\n"
            "With the BPO and police report, you or the prosecutor can file a criminal case. "
            "Free legal aid is available through the PAO (Public Attorney's Office).\n\n"
            "📋 **Legal Basis:** RA 9262 (Anti-Violence Against Women and Their Children Act); "
            "RA 7160, Section 389 — BPO authority of Punong Barangay"
        ),
    },
    {
        "triggers": {"blotter", "police", "report", "incident", "crime", "assault", "fight", "mauling", "threat", "threatening"},
        "answer": (
            "**How to File a Barangay Blotter Report**\n\n"
            "Here is the step-by-step process:\n\n"
            "**Step 1 — Go to the Barangay Hall**\n"
            "Visit the Barangay Hall and ask for the Barangay Secretary or duty tanod. "
            "You can file a blotter anytime — barangays are required to accept reports.\n\n"
            "**Step 2 — Narrate the incident**\n"
            "Give a clear account of what happened: date, time, place, names of parties involved, "
            "and witnesses. The secretary will write this in the Barangay Blotter book.\n\n"
            "**Step 3 — Sign the entry**\n"
            "Sign the blotter entry and request a certified copy — it is free of charge.\n\n"
            "**Step 4 — Request mediation (if applicable)**\n"
            "For disputes between neighbors, the barangay will schedule mediation. "
            "For criminal matters (assault, threats), the barangay can refer the case to the police.\n\n"
            "**Step 5 — Follow up**\n"
            "Keep your copy of the blotter. For serious crimes, also file a report at the PNP station.\n\n"
            "📋 **Legal Basis:** RA 7160, Section 389 — Duty of the Punong Barangay to "
            "maintain peace and order"
        ),
    },
    {
        "triggers": {"property", "land", "boundary", "encroachment", "trespassing", "fence", "wall", "easement"},
        "answer": (
            "**Property Boundary Dispute at the Barangay Level**\n\n"
            "Here is the step-by-step process:\n\n"
            "**Step 1 — Gather your documents**\n"
            "Collect your land title (TCT or OCT), tax declaration, and any survey plans. "
            "These will be key evidence during mediation.\n\n"
            "**Step 2 — File a complaint at the Barangay**\n"
            "Go to the Barangay Hall and report the boundary dispute. "
            "The barangay has jurisdiction over disputes between residents of the same barangay.\n\n"
            "**Step 3 — Barangay mediation**\n"
            "The Lupon will summon both parties. Each side presents their documents. "
            "The goal is an amicable settlement (e.g., agree on a boundary line).\n\n"
            "**Step 4 — If no agreement**\n"
            "If mediation fails, the barangay issues a Certificate to File Action (CFA). "
            "You may then file a case with the Regional Trial Court (RTC) for land disputes.\n\n"
            "**Step 5 — Geodetic survey**\n"
            "For complex boundary issues, a licensed geodetic engineer can be hired to "
            "conduct an official relocation survey.\n\n"
            "📋 **Legal Basis:** RA 7160, Sections 399–422 (KP Law); "
            "PD 1529 (Property Registration Decree)"
        ),
    },
    {
        "triggers": {"solo", "parent", "single", "solo parent", "pwd", "disability", "senior", "elderly", "indigent"},
        "answer": (
            "**Benefits for Solo Parents, PWDs, and Senior Citizens at the Barangay**\n\n"
            "**Solo Parents (RA 8972)**\n"
            "- Apply for a Solo Parent ID at the DSWD or your barangay\n"
            "- 10% discount on goods and services\n"
            "- Parental leave benefits (7 days)\n"
            "- Priority in government programs\n\n"
            "**Persons with Disabilities — PWD (RA 7277 + RA 10754)**\n"
            "- Apply for a PWD ID at the barangay or City/Municipal Health Office\n"
            "- 20% discount + VAT exemption on medicine, transport, restaurants, hotels\n"
            "- Priority lanes in all government offices\n\n"
            "**Senior Citizens (RA 9994 — Expanded Senior Citizens Act)**\n"
            "- Register for a Senior Citizen ID at the Office for Senior Citizens Affairs (OSCA) "
            "in your barangay or city hall\n"
            "- 20% discount + VAT exemption on medicine, food, transport, and services\n"
            "- Monthly social pension for indigent seniors (₱500/month via DSWD)\n\n"
            "📋 **Legal Basis:** RA 8972 (Solo Parents' Welfare Act); "
            "RA 7277 as amended by RA 10754 (Magna Carta for PWDs); "
            "RA 9994 (Expanded Senior Citizens Act)"
        ),
    },
]


def _match_legal_topic(query: str) -> Optional[str]:
    """Return a structured answer if the query matches a known legal topic."""
    q_keys = _keywords(query)
    if not q_keys:
        return None

    best_answer = None
    best_overlap = 0

    for topic in _LEGAL_TOPICS:
        overlap = len(q_keys & topic["triggers"])
        # Match if 1 strong keyword OR 2+ overlapping keywords
        strong = any(len(k) >= 6 for k in (q_keys & topic["triggers"]))
        if (overlap >= 2 or (overlap >= 1 and strong)) and overlap > best_overlap:
            best_overlap = overlap
            best_answer = topic["answer"]

    return best_answer


def _faq_search(query: str) -> Optional[str]:
    """Keyword search over FAQ JSON. Returns best answer or None."""
    data = load_faq_data()
    if not data:
        return None

    q_lower = re.sub(r"[^\w\s]", "", query.lower())
    q_keys  = _keywords(query)

    if not q_keys:
        return None

    best_answer = None
    best_score  = 0.0

    for cat in data.get("categories", []):
        for item in cat.get("questions", []):
            candidate = re.sub(r"[^\w\s]", "", item.get("question", "").lower())
            c_keys    = _keywords(candidate)
            if not c_keys:
                continue
            overlap = len(q_keys & c_keys) / max(len(q_keys), len(c_keys))
            if q_lower in candidate:
                overlap = max(overlap, 0.9)
            if overlap > best_score:
                best_score  = overlap
                best_answer = item.get("answer", "") or None

    return best_answer if best_score >= 0.40 else None


# ── Public API ────────────────────────────────────────────────────────────────
def chat_response(sender: int, message: str) -> dict:
    """
    1. Try built-in legal topic answers (structured, step-by-step)
    2. Try FAQ JSON search
    3. Fallback message

    Returns: { "response": str, "sender": int }
    """
    text = message.strip()

    # 1 — structured legal topic
    topic_hit = _match_legal_topic(text)
    if topic_hit:
        logger.info(f"[CHATBOT] Matched legal topic for: {text[:60]}")
        return {"response": topic_hit, "sender": sender}

    # 2 — FAQ search
    faq_hit = _faq_search(text)
    if faq_hit:
        logger.info(f"[CHATBOT] Matched FAQ for: {text[:60]}")
        return {"response": faq_hit, "sender": sender}

    # 3 — fallback
    return {
        "response": (
            "I don't have a specific answer for that right now. "
            "For accurate barangay legal assistance, please visit your Barangay Hall "
            "or contact the Lupong Tagapamayapa directly. "
            "You may also consult the Public Attorney's Office (PAO) for free legal advice."
        ),
        "sender": sender,
    }


# ── Bootstrap ─────────────────────────────────────────────────────────────────
load_faq_data()
