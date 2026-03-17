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


# ── Language detection ────────────────────────────────────────────────────────
_TAGALOG_INDICATORS = {
    "ako", "ko", "ka", "mo", "siya", "niya", "kami", "tayo", "kayo", "sila",
    "ang", "ng", "mga", "sa", "na", "at", "ay", "hindi", "oo", "po", "ho",
    "yung", "yun", "iyon", "ito", "dito", "doon", "nandito", "nandoon",
    "gusto", "ayaw", "kailangan", "pwede", "maaari", "dapat", "sana",
    "paano", "bakit", "saan", "sino", "kailan", "magkano", "gaano",
    "ito", "iyon", "ganito", "ganyan", "ganoon", "kaya", "pero", "dahil",
    "kapag", "kung", "para", "din", "rin", "lang", "naman", "talaga",
    "ngayon", "bukas", "kahapon", "minsan", "palagi", "lagi",
    "ayaw", "magbayad", "kapitbahay", "kapit", "bahay", "ingay",
    "maingay", "away", "reklamo", "ireklamo", "magreklamo",
    "kumuha", "makakuha", "humingi", "pumunta", "magpunta",
}


def _is_tagalog(text: str) -> bool:
    """Return True if the message appears to be primarily Tagalog."""
    words = set(re.sub(r"[^\w\s]", "", text.lower()).split())
    tagalog_hits = len(words & _TAGALOG_INDICATORS)
    return tagalog_hits >= 2 or (tagalog_hits == 1 and len(words) <= 5)


# ── Tagalog → English keyword expansion ──────────────────────────────────────
_TAGALOG_MAP = {
    # Actions
    "kumuha": "get clearance certificate document",
    "makakuha": "get clearance certificate document",
    "magsampa": "file complaint report blotter",
    "magreklamo": "complaint report file blotter",
    "ireklamo": "complaint report file blotter",
    "idemanda": "file case complaint",
    "magfile": "file complaint",
    "iulat": "report blotter",
    "ipaalam": "report inform",
    "humingi": "request get",
    "magpunta": "go visit barangay",
    "pumunta": "go visit barangay",
    "makipag-usap": "mediation talk",
    "makiusap": "mediation",
    "ipahinto": "stop report complaint",
    # Topics
    "reklamo": "complaint report",
    "dokumento": "document certificate clearance",
    "sertipiko": "certificate clearance",
    "requirements": "requirements clearance document",
    "patunay": "certificate proof document",
    "pahintulot": "clearance permit",
    "pagpapatunay": "certificate clearance",
    "ingay": "noise disturbance",
    "away": "dispute fight complaint",
    "basag": "broken damage complaint",
    "utang": "debt",
    "pautang": "debt loan",
    "bayad": "payment debt",
    "bayaran": "pay debt",
    "pera": "money debt",
    "lupa": "land property boundary",
    "lupain": "land property boundary",
    "bakod": "fence boundary property",
    "hangganan": "boundary property land",
    "bahay": "house property",
    "kapitbahay": "neighbor",
    "kapit-bahay": "neighbor",
    "kalapit": "neighbor",
    "pamilya": "family",
    "bata": "children minor",
    "babae": "women",
    "asawa": "spouse husband wife",
    "kasamahan": "partner spouse",
    "kabit": "affair infidelity",
    "kalayaan": "separation rights",
    "karapatan": "rights",
    "tulong": "help assistance legal",
    "impormasyon": "information",
    "proseso": "process steps",
    "paano": "how process steps",
    "saan": "where barangay",
    "sino": "who official",
    "kailan": "when schedule",
    "magkano": "how much fee cost",
    "libre": "free cost",
    "bayad": "fee cost payment",
    "mabilis": "fast quick process",
    "matagal": "long time process",
    "lupon": "lupon mediation kp",
    "punong": "punong barangay captain",
    "kapitan": "barangay captain",
    "tanod": "tanod security barangay",
    "huwes": "judge court",
    "abogado": "lawyer legal",
    "pulis": "police report",
    "ospital": "hospital medical",
    "batas": "law legal",
    "kaso": "case complaint court",
    "proteksyon": "protection order bpo",
    "kalayaan": "rights separation",
}

_VAGUE_INTENT_WORDS = {
    "requirements", "process", "paano", "proseso", "impormasyon",
    "information", "details", "steps", "guide", "tulong", "help",
    "kumuha", "makakuha", "humingi", "gusto", "kailangan", "need",
    "want", "dokumento", "document", "certificate", "sertipiko",
}

_CLARIFICATION_RESPONSE = (
    "I'd be happy to help! Could you please specify what you need assistance with?\n\n"
    "Maaari mo akong tanungin tungkol sa:\n\n"
    "• 📋 **Barangay Clearance** — requirements, process, fees\n"
    "• ⚖️ **Mediation / Summoning** — KP process, dispute resolution\n"
    "• 💸 **Debt / Utang** — neighbour refuses to pay\n"
    "• 🏠 **Property / Lupa** — boundary disputes, encroachment\n"
    "• 🚨 **VAWC / Abuse** — protection orders, domestic violence\n"
    "• 📝 **Blotter / Reklamo** — how to file an incident report\n"
    "• 🔇 **Noise / Ingay** — noise disturbance, curfew\n"
    "• 👴 **Senior / PWD / Solo Parent** — benefits and discounts\n\n"
    "Just type your concern and I'll guide you step by step! 😊"
)


def _expand_tagalog(text: str) -> str:
    """Replace Tagalog words with English equivalents for better topic matching."""
    words = text.lower().split()
    expanded = []
    for word in words:
        clean = re.sub(r"[^\w]", "", word)
        if clean in _TAGALOG_MAP:
            expanded.append(_TAGALOG_MAP[clean])
        else:
            expanded.append(word)
    return " ".join(expanded)


def _is_vague(text: str) -> bool:
    """Return True if message has intent but no specific topic."""
    words = set(re.sub(r"[^\w\s]", "", text.lower()).split())
    has_vague_intent = bool(words & _VAGUE_INTENT_WORDS)
    if not has_vague_intent:
        return False
    # Check if there's any specific topic keyword present
    all_triggers = set()
    for topic in _LEGAL_TOPICS:
        all_triggers |= topic["triggers"]
    all_triggers |= set(_TAGALOG_MAP.keys())
    specific = words & (all_triggers - _VAGUE_INTENT_WORDS)
    return len(specific) == 0


# ── Built-in structured legal topic answers ───────────────────────────────────
# Each entry: list of trigger keywords → structured answer
# A query matches if it shares ≥2 trigger keywords (or 1 strong unique keyword)

_LEGAL_TOPICS = [
    {
        "triggers": {"summon", "summoning", "summons", "mediation", "katarungang", "pambarangay", "lupon", "lupong", "tagapamayapa", "kp", "pagpapamagitan", "pagkakasundo", "pangkat", "usapin"},
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
        "triggers": {"debt", "utang", "bayad", "bayaran", "owe", "owes", "refuses", "pay", "collection", "borrow", "borrowed", "lending", "loan", "pautang", "pera", "hindi", "nagbabayad"},
        "answer": (
            "**Neighbour Refuses to Pay Debt — What You Can Do**\n\n"
            "We understand how frustrating this situation can be. Here is the step-by-step process to resolve it:\n\n"
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
        "answer_tl": (
            "**Kapitbahay Ayaw Magbayad ng Utang — Ano ang Dapat Gawin**\n\n"
            "Naiintindihan namin kung gaano ito kafrustrating. Narito ang hakbang-hakbang na proseso:\n\n"
            "**Hakbang 1 — Magpadala ng demand letter**\n"
            "Magpadala ng nakasulat na liham na humihingi sa iyong kapitbahay na magbayad. "
            "Magtago ng kopya. Bigyan sila ng makatwirang deadline (7–15 araw).\n\n"
            "**Hakbang 2 — Magreklamo sa Barangay**\n"
            "Kung hindi sila sumasagot, pumunta sa Barangay Hall at mag-file ng reklamo. "
            "Magdala ng patunay ng utang (kasulatan, resibo, mensahe, mga saksi).\n\n"
            "**Hakbang 3 — Pagpapamagitan sa Barangay**\n"
            "Ipapatawag ng Punong Barangay ang iyong kapitbahay para sa mediation. "
            "Magbibigay ng pagkakataon sa magkabilang panig na magsalita. "
            "Sisikaping maabot ang mapayapang kasunduan.\n\n"
            "**Hakbang 4 — Kasunduan**\n"
            "Kung sumasang-ayon ang kapitbahay na magbayad, isusulat ang kasunduan sa harap ng barangay. "
            "Ito ay may bisa ng panghuling hatol ng korte at maipapatupad.\n\n"
            "**Hakbang 5 — Certificate to File Action**\n"
            "Kung tumatanggi ang kapitbahay sa mediation o hindi sumusunod sa kasunduan, "
            "maglalabas ang barangay ng Certificate to File Action (CFA). "
            "Maaari ka nang mag-file ng kaso sa Municipal Trial Court.\n\n"
            "💡 **Tandaan:** Para sa utang na ≤ ₱400,000, maaari kang mag-file ng Small Claims case — "
            "hindi na kailangan ng abogado.\n\n"
            "📋 **Legal na Batayan:** RA 7160, Mga Seksyon 399–422 (KP Law); "
            "Rule of Procedure for Small Claims Cases (A.M. No. 08-8-7-SC)"
        ),
    },
    {
        "triggers": {"clearance", "certificate", "residency", "cedula", "katibayan", "pahintulot", "pagpapatunay", "sertipiko"},
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
        "answer_tl": (
            "**Paano Kumuha ng Barangay Clearance**\n\n"
            "Narito ang hakbang-hakbang na proseso:\n\n"
            "**Hakbang 1 — Pumunta sa Barangay Hall**\n"
            "Bisitahin ang inyong lokal na Barangay Hall sa oras ng opisina (karaniwan ay 8AM–5PM, Lunes–Biyernes).\n\n"
            "**Hakbang 2 — Magdala ng mga kinakailangan**\n"
            "- Valid na government ID\n"
            "- Patunay ng tirahan (utility bill, kontrata sa upa, o deklarasyon mula sa kapitbahay)\n"
            "- Cedula (Community Tax Certificate) — makukuha sa parehong barangay o City Hall\n\n"
            "**Hakbang 3 — Punan ang form**\n"
            "Humingi at punan ang application form para sa Barangay Clearance sa counter.\n\n"
            "**Hakbang 4 — Bayaran ang bayarin**\n"
            "Bayaran ang processing fee (karaniwang ₱50–₱200, depende sa barangay).\n\n"
            "**Hakbang 5 — Tanggapin ang clearance**\n"
            "Ang clearance ay karaniwang inilalabas sa parehong araw o sa loob ng 1–3 araw ng trabaho. "
            "Ito ay may bisa na 6 na buwan hanggang 1 taon depende sa barangay.\n\n"
            "📋 **Legal na Batayan:** RA 7160 (Local Government Code), Seksyon 389 — "
            "Mga Kapangyarihan at Tungkulin ng Punong Barangay"
        ),
    },
    {
        "triggers": {"noise", "disturbance", "videoke", "karaoke", "loud", "curfew", "ordinance", "nuisance", "ingay", "maingay", "gabi", "bisyo"},
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
        "triggers": {"affair", "kabit", "infidelity", "cheating", "husband", "wife", "asawa", "marital", "selingkuh"},
        "answer": (
            "**Reporting a Marital Affair / Infidelity**\n\n"
            "We understand this is a painful situation, and we're here to help you understand your rights. "
            "Here is what you can do:\n\n"
            "**Step 1 — Understand barangay jurisdiction**\n"
            "Marital infidelity (affair) is not directly a barangay-level offense. "
            "However, the barangay can help if the affair involves psychological abuse, "
            "threats, or abandonment under RA 9262 (VAWC).\n\n"
            "**Step 2 — Go to the Barangay VAWC Desk**\n"
            "Visit your Barangay Hall and speak with the VAWC Desk Officer. "
            "Explain your situation. They will assess if RA 9262 applies "
            "(e.g., emotional/psychological abuse caused by the affair).\n\n"
            "**Step 3 — Request a Barangay Protection Order (BPO) if needed**\n"
            "If you feel threatened or emotionally harmed, "
            "the Punong Barangay can issue a BPO on the same day.\n\n"
            "**Step 4 — For legal separation or annulment**\n"
            "These are handled by the Family Court, not the barangay. "
            "You may consult the Public Attorney's Office (PAO) for free legal advice.\n\n"
            "**Step 5 — File a criminal case (if applicable)**\n"
            "Concubinage (husband) or adultery (wife) are criminal offenses under the Revised Penal Code. "
            "These must be filed in regular courts. Consult PAO or a private lawyer.\n\n"
            "📋 **Legal Basis:** RA 9262 (Anti-VAWC Act) — psychological abuse; "
            "Revised Penal Code, Articles 333–334 — Adultery and Concubinage; "
            "RA 7160, Section 389 — Barangay VAWC Desk"
        ),
    },
    {
        "triggers": {"vawc", "violence", "abuse", "domestic", "battered", "rape", "harassment", "stalking", "women", "children", "psychological"},
        "answer": (
            "**Violence Against Women and Children (VAWC)**\n\n"
            "We hear you, and you are not alone. Your safety is the priority. "
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
        "triggers": {"blotter", "police", "report", "incident", "crime", "assault", "fight", "mauling", "threat", "threatening", "reklamo", "ireklamo", "away", "suntok", "sigawan", "away"},
        "answer": (
            "**How to File a Barangay Blotter Report**\n\n"
            "We're sorry to hear you've been through a difficult situation. "
            "Here is how to file a blotter report at your barangay:\n\n"
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
        "triggers": {"property", "land", "boundary", "encroachment", "trespassing", "fence", "wall", "easement", "lupa", "lupain", "bakod", "hangganan", "bahay", "ari-arian"},
        "answer": (
            "**Property Boundary Dispute at the Barangay Level**\n\n"
            "We understand property disputes can be stressful. "
            "Here is the step-by-step process to resolve it through the barangay:\n\n"
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


def _match_legal_topic(query: str, tagalog: bool = False) -> Optional[str]:
    """Return a structured answer if the query matches a known legal topic."""
    q_keys = _keywords(query)
    # Also include short but meaningful words (vawc, kp, etc.) even if len <= 2
    q_keys_raw = set(re.sub(r"[^\w\s]", "", query.lower()).split())

    best_topic = None
    best_overlap = 0

    for topic in _LEGAL_TOPICS:
        matched = (q_keys | q_keys_raw) & topic["triggers"]
        overlap = len(matched)
        strong = any(len(k) >= 4 for k in matched)
        if (overlap >= 2 or (overlap >= 1 and strong)) and overlap > best_overlap:
            best_overlap = overlap
            best_topic = topic

    if best_topic is None:
        return None
    if tagalog and best_topic.get("answer_tl"):
        return best_topic["answer_tl"]
    return best_topic["answer"]


# ── Call-to-action (Forms Hub) ────────────────────────────────────────────────
_CTA = (
    "\n\n---\n"
    "💡 **File online through the BLA App**\n"
    "You can file a complaint or request a mediation/summon schedule directly "
    "through the **Barangay Legal Aid app**. Tap **Forms Hub** from the home screen to get started."
)

# Keywords in the query OR answer that trigger the CTA
_CTA_TRIGGERS = {
    "complaint", "complain", "file", "report", "blotter", "mediation",
    "summon", "summoning", "schedule", "case", "dispute", "kp", "lupon",
    "debt", "utang", "vawc", "abuse", "violence", "neighbor", "neighbour",
    "boundary", "property", "assault", "threat", "harassment",
}


def _should_add_cta(query: str, answer: str) -> bool:
    """Return True if the query or answer involves actionable complaints/reports."""
    combined = (query + " " + answer).lower()
    words = set(re.sub(r"[^\w\s]", "", combined).split())
    return bool(words & _CTA_TRIGGERS)


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


# ── Greeting detection & response ────────────────────────────────────────────
_GREETING_WORDS = {
    "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
    "kamusta", "kumusta", "magandang umaga", "magandang hapon", "magandang gabi",
    "musta", "sup", "yo", "greetings", "howdy", "helo", "hellow", "ello",
    "good day", "maayong buntag", "maayong hapon", "maayong gabii",
}

_GREETING_RESPONSE = (
    "Hello! Welcome to the **Barangay Legal Aid (BLA) Assistant**. 👋\n\n"
    "I'm here to help you with barangay-level legal concerns. "
    "What can I assist you with today?\n\n"
    "Here are some things you can ask me about:\n\n"
    "• 📋 **Barangay Clearance** — How to get one, requirements, fees\n"
    "• ⚖️ **Mediation & Summoning** — KP process, how disputes are resolved\n"
    "• 💸 **Debt / Collection** — Neighbour refuses to pay, what to do\n"
    "• 🏠 **Property Disputes** — Boundary issues, encroachment\n"
    "• 🚨 **VAWC / Abuse** — Violence against women and children, protection orders\n"
    "• 📝 **Blotter Report** — How to file an incident report\n"
    "• 🔇 **Noise & Disturbance** — Curfew violations, noise ordinances\n"
    "• 👴 **Senior / PWD / Solo Parent** — Benefits and discounts\n\n"
    "Just type your question and I'll guide you step by step!"
)


def _is_greeting(message: str) -> bool:
    """Return True if the message is a greeting with no legal content."""
    text = message.lower().strip()
    # Remove punctuation
    text = re.sub(r"[^\w\s]", "", text)
    words = set(text.split())
    # Greeting if any greeting word matches AND message is short (≤6 words)
    return bool(words & _GREETING_WORDS) and len(text.split()) <= 6


# ── Conversational context enrichment ────────────────────────────────────────
_FOLLOWUP_SIGNALS = {
    "how long", "how much", "paano", "what next", "then what", "after that",
    "next step", "what if", "what happens", "ano pa", "tapos", "saan",
    "bakit", "magkano", "gaano", "pano", "what about", "and then",
    "can i", "do i need", "is it free", "free ba", "fee", "bayad",
    "how do i", "where do i", "sino", "who", "when", "kailan",
}


def _is_followup(message: str) -> bool:
    """Return True if message looks like a follow-up (short or contains follow-up signals)."""
    text = message.lower().strip()
    if len(text.split()) <= 4:
        return True
    return any(signal in text for signal in _FOLLOWUP_SIGNALS)


def _enrich_with_history(message: str, history: list) -> str:
    """
    If message is a follow-up, find the last meaningful user query in history
    and prepend its topic keywords to the current message.
    history: list of {"role": "user"|"assistant", "content": str}
    """
    if not history or not _is_followup(message):
        return message

    # Walk history backwards to find the last substantial user message
    for entry in reversed(history):
        if entry.get("role") == "user":
            prev = entry.get("content", "").strip()
            if len(prev.split()) > 3 and prev.lower() != message.lower():
                # Prepend prev topic keywords to current query
                prev_keys = _keywords(prev)
                if prev_keys:
                    enriched = f"{' '.join(prev_keys)} {message}"
                    logger.info(f"[CHATBOT] Enriched follow-up: '{message}' → '{enriched[:80]}'")
                    return enriched
                break

    return message


# ── Public API ────────────────────────────────────────────────────────────────

def get_local_answer(message: str, history: list | None = None) -> Optional[str]:
    """
    Returns a local answer string if we have one, or None to let the
    chatbot service / HF API handle it.

    Priority:
      1. Greeting
      2. Vague/unspecified query → ask for clarification
      3. Built-in legal topic (original + Tagalog-expanded + history-enriched)
      4. FAQ search
    """
    text = message.strip()
    tl = _is_tagalog(text)
    expanded = _expand_tagalog(text)
    enriched = _enrich_with_history(expanded, history or [])

    # 1 — greeting
    if _is_greeting(text):
        logger.info(f"[CHATBOT] Greeting detected: {text[:40]}")
        return _GREETING_RESPONSE

    # 2 — vague query (has intent but no specific topic)
    if _is_vague(text) and _is_vague(expanded):
        logger.info(f"[CHATBOT] Vague query, asking for clarification: {text[:60]}")
        return _CLARIFICATION_RESPONSE

    # 3 — structured legal topic (try all variants, respect detected language)
    topic_hit = (
        _match_legal_topic(enriched, tagalog=tl)
        or _match_legal_topic(expanded, tagalog=tl)
        or _match_legal_topic(text, tagalog=tl)
    )
    if topic_hit:
        logger.info(f"[CHATBOT] Matched legal topic for: {text[:60]}")
        if _should_add_cta(text, topic_hit):
            topic_hit += _CTA
        return topic_hit

    # 4 — FAQ search
    faq_hit = _faq_search(enriched) or _faq_search(expanded) or _faq_search(text)
    if faq_hit:
        logger.info(f"[CHATBOT] Matched FAQ for: {text[:60]}")
        if _should_add_cta(text, faq_hit):
            faq_hit += _CTA
        return faq_hit

    return None


def chat_response(sender: int, message: str, history: list | None = None) -> dict:
    """
    Full fallback pipeline when chatbot service and HF API are unavailable.
    Returns: { "response": str, "sender": int }
    """
    answer = get_local_answer(message, history)
    if answer:
        return {"response": answer, "sender": sender}

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
