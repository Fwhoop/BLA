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
    # animal bite
    "nakagat": "animal bite injury",
    "kinagat": "animal bite injury",
    "kagat":   "animal bite injury",
    "aso":     "dog animal",
    "pusa":    "cat animal",
    # drugs
    "droga":    "illegal drugs prohibited",
    "shabu":    "illegal drugs prohibited",
    "marijuana": "illegal drugs cannabis",
    "marijuana": "illegal drugs cannabis",
    # theft
    "magnakaw":  "theft robbery steal",
    "nanakaw":   "theft robbery stolen",
    "magnanakaw":"theft robbery criminal",
    "ninakaw":   "theft robbery stolen",
    "pagnanakaw":"theft robbery",
    # fraud
    "panloloko": "estafa fraud swindling",
    "daya":      "fraud estafa cheat",
    "lokohin":   "fraud estafa deceive",
    # environment
    "basura":    "garbage waste environment",
    # smoking
    "sigarilyo": "smoking cigarette",
    "usok":      "smoke smoking",
    # bullying / violence
    "pang-aapi":   "bullying harassment abuse",
    "panggugulpi": "physical assault mauling",
    # juvenile
    "kabataan": "youth minor juvenile",
    "menor":    "minor juvenile curfew",
    # corruption
    "suhol":     "bribery corruption",
    "korupsyon": "corruption bribery",
    # cybercrime
    "manloloko": "fraud online cybercrime",
    "scam":      "fraud online cybercrime",
    "hacked":    "cybercrime online",
    "libelo":    "libel cybercrime defamation",
    # eviction / rent
    "nangungupahan": "tenant rent eviction",
    "paupahan":      "rent landlord tenant",
    "renta":         "rent payment",
    "upa":           "rent lease",
    "pinaalis":      "evicted eviction",
    "inalis":        "evicted removed",
    # labor
    "trabaho":   "work employment labor",
    "sweldo":    "salary wage payment",
    "tinanggal": "fired dismissed terminated",
    "tanggal":   "fired dismissed terminated",
    # kasambahay
    "katulong":  "helper kasambahay domestic worker",
    "yaya":      "helper kasambahay domestic worker",
    # consumer
    "mamahaling": "overpricing expensive consumer",
    "dayaan":     "fraud consumer cheat",
    # threats
    "tinakot":   "threats threatening coercion",
    "banta":     "threats threatening",
    "pananakot": "coercion intimidation threats",
    "pangongotong": "extortion bribery",
    # physical injury
    "sinuntok":  "physical injury assault punch",
    "binugbog":  "physical injury mauling beaten",
    "nasaktan":  "injured physical harm",
    "bugbog":    "mauling physical assault",
    # fire / arson
    "nasunog":   "fire arson burned",
    "sinunog":   "arson fire burned",
    "sunog":     "fire arson",
    # trespassing
    "pumasok":   "trespass illegal entry",
    "nagsalakay":"trespass intrusion",
    # inheritance
    "pamana":    "inheritance estate succession",
    "mana":      "inheritance estate",
    "namatay":   "deceased estate inheritance",
    # marriage
    "kasal":     "marriage wedding",
    "hiwalay":   "separation annulment divorce",
    "annul":     "annulment marriage void",
    # mental health
    "nalulungkot": "depression mental health",
    "gusto mamatay": "suicidal mental health crisis",
    # privacy
    "naglabas ng impormasyon": "data privacy breach",
    # election
    "eleksyon":  "election vote",
    "boto":      "vote election voter",
    "bumoto":    "vote election",
    # squatting
    "demolisyon": "demolition eviction informal settler",
    "relokasyon": "relocation housing informal settler",
    "palipat":    "relocation eviction",
    # OFW
    "abroad":    "overseas ofw migrant",
    "nagtatrabaho sa ibang bansa": "ofw overseas worker",
    # voyeurism
    "kuha ng litrato": "photo recording voyeurism",
    "video nang walang pahintulot": "voyeurism recording consent",
    # free legal
    "libre abogado": "free legal aid pao",
    "walang pera abogado": "free legal assistance pao",
    # oral defamation
    "minura":    "oral defamation slander insult",
    "nagmura":   "oral defamation cursing slander",
    "panlalait": "defamation insult slander",
    # rape / sexual assault
    "ginahasa":  "rape sexual assault victim",
    "inabuso":   "sexual abuse victim",
    "nang-rape": "rape sexual assault",
    # trafficking
    "inalipin":  "trafficking exploited victim",
    "biktima":   "victim crime trafficking",
    # gambling
    "sugal":     "gambling illegal bet",
    "masugal":   "gamble bet illegal",
    "jueteng":   "illegal gambling jueteng",
    # missing person
    "nawala":    "missing disappeared person",
    "hinahanap": "missing looking searching person",
    # child support / custody
    "suporta bata": "child support custody",
    "iniwan":    "abandoned abandonment",
    "pag-aalalay": "support custody child",
    # adoption
    "inaampon":  "adoption foster child",
    "inampon":   "adopted child foster",
    "ampunin":   "adopt foster child",
    "ulila":     "orphan adoption",
    # maternity / paternity
    "buntis":    "pregnant maternity leave",
    "magpapaanak": "pregnancy maternity leave",
    # building / construction
    "walang permit itayo": "no building permit illegal construction",
    "itayo":     "construction build structure",
    # agrarian
    "magsasaka": "farmer agrarian land",
    "bukid":     "farm agricultural land",
    "kasama":    "tenant farmer agrarian",
    # SSS / PhilHealth / Pag-IBIG
    "pensiyon":  "pension sss retirement benefit",
    "kontribusyon": "contribution sss philhealth pagibig",
    # loan shark
    "bombay":    "loan shark lender illegal",
    "limang anim": "5-6 loan shark usury",
    # child labor
    "bata nagtatrabaho": "child labor working minor",
    # disaster
    "bagyo":     "typhoon disaster calamity",
    "baha":      "flood disaster calamity",
    "lindol":    "earthquake disaster calamity",
    "sakuna":    "disaster calamity emergency",
    "lumikas":   "evacuate evacuation disaster",
    # electricity / water theft
    "kuryente":  "electricity power",
    "jumper":    "illegal connection electricity theft",
    "tubig":     "water pilferage theft",
    # hazing
    "padyak":    "hazing initiation physical",
    "initian":   "hazing initiation rite",
    # arrest / rights
    "naaresto":  "arrested detained rights",
    "nakulong":  "detained imprisoned rights",
    "pulis kinuha": "arrested police detained",
    # farming / wildlife
    "pagputol ng puno": "illegal logging tree cutting",
    "pangingisda ilegal": "illegal fishing BFAR",
    # endo / contractualization
    "kontraktwal": "contractual endo employee",
    "hindi regular": "not regular employee endo",
    # business permit
    "negosyo":   "business permit license",
    "tindahan permit": "store business permit",
    # OSAEC
    "inabuso online": "online sexual exploitation OSAEC",
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
        "triggers": {"debt", "utang", "bayad", "bayaran", "owe", "owes", "pay", "collection", "borrow", "borrowed", "lending", "loan", "pautang", "pera", "nagbabayad"},
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
        "triggers": {"animal", "bite", "dog", "cat", "aso", "pusa", "nakagat", "kinagat", "kagat", "rabies", "wound", "injury", "bitten"},
        "answer": (
            "**Animal Bite — What to Do and Your Legal Rights**\n\n"
            "**Step 1 — Seek immediate medical attention**\n"
            "Go to the nearest hospital or Animal Bite Treatment Center (ABTC) immediately. "
            "Wash the wound with soap and water for at least 15 minutes. "
            "Anti-rabies vaccine and Rabies Immune Globulin (RIG) are provided FREE in government ABTCs.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "Report the incident at your Barangay Hall. The barangay will document the case "
            "and coordinate with the City/Municipal Veterinarian to locate and quarantine the animal.\n\n"
            "**Step 3 — File a complaint against the animal owner**\n"
            "If the animal has an owner, the barangay can summon them for mediation. "
            "The owner is liable for medical expenses, damages, and loss of income "
            "under the Civil Code and RA 9482.\n\n"
            "**Step 4 — Barangay mediation for damages**\n"
            "The Lupon will facilitate settlement between you and the animal owner "
            "covering hospital bills, treatment costs, and moral damages.\n\n"
            "**Step 5 — Escalate if owner refuses**\n"
            "If the owner refuses to cooperate, the barangay issues a Certificate to File Action (CFA). "
            "You may sue in court for damages. The owner may also face criminal liability.\n\n"
            "📋 **Legal Basis:** RA 9482 (Anti-Rabies Act of 2007) — Sections 6 & 7, owner liability; "
            "Civil Code of the Philippines, Article 2183 — possessor of animal liable for damages; "
            "RA 7160, Sections 399–422 — KP mediation"
        ),
    },
    {
        "triggers": {"drugs", "illegal", "prohibited", "shabu", "marijuana", "cannabis", "pusher", "drug", "droga", "addict", "addiction", "substance", "peddling", "selling drugs", "narkotiko"},
        "answer": (
            "**Illegal Drugs — Reporting and Barangay Procedures**\n\n"
            "**Step 1 — Report to the Barangay**\n"
            "Report suspected drug activity to the Punong Barangay or Barangay Tanod immediately. "
            "You may report anonymously. The barangay is mandated by law to act on drug complaints.\n\n"
            "**Step 2 — Barangay Anti-Drug Abuse Council (BADAC)**\n"
            "Every barangay has a BADAC (Barangay Anti-Drug Abuse Council) that coordinates "
            "drug-related concerns. They will coordinate with the PNP and PDEA.\n\n"
            "**Step 3 — Do NOT confront the suspect**\n"
            "Do not attempt to apprehend or confront the suspect yourself. "
            "Let law enforcement handle the operation.\n\n"
            "**Step 4 — For drug users seeking help**\n"
            "Drug dependents who voluntarily surrender are entitled to rehabilitation, not imprisonment. "
            "Go to the barangay or nearest drug treatment and rehabilitation center. "
            "PDEA and DOH provide free rehabilitation programs.\n\n"
            "**Step 5 — Community-Based Rehabilitation (CBR)**\n"
            "The barangay runs Community-Based Drug Rehabilitation Programs for low-risk users. "
            "Participants avoid prosecution by completing the program.\n\n"
            "📋 **Legal Basis:** RA 9165 (Comprehensive Dangerous Drugs Act of 2002) — "
            "Sections 23 & 54, voluntary surrender and rehabilitation; "
            "RA 10640 — amendment on drug operations; "
            "RA 7160, Section 389 — BADAC mandate"
        ),
    },
    {
        "triggers": {"theft", "robbery", "steal", "stolen", "stole", "robbed", "thief", "burglar", "burglary", "snatching", "snatcher", "nanakaw", "ninakaw", "magnanakaw", "pagnanakaw", "holdap", "holdup"},
        "answer": (
            "**Theft or Robbery — What to Do**\n\n"
            "**Step 1 — Ensure your safety first**\n"
            "If you are in immediate danger, call 911 or go to the nearest barangay or police station.\n\n"
            "**Step 2 — File a Barangay Blotter**\n"
            "Go to the Barangay Hall and report the incident. The barangay will record it in the blotter. "
            "Bring any evidence: CCTV footage, witness accounts, description of the suspect.\n\n"
            "**Step 3 — File a Police Report**\n"
            "Simultaneously file a report at the nearest PNP station. "
            "Theft and robbery are criminal cases handled by the police and courts — "
            "not by barangay mediation.\n\n"
            "**Step 4 — Barangay jurisdiction note**\n"
            "Theft between neighbors (small amounts, first offense) may go through barangay mediation "
            "for restitution. Robbery (with force or violence) is always a police/court matter.\n\n"
            "**Step 5 — Recover your property**\n"
            "File an inventory of stolen items. Report to the nearest pawnshop or market "
            "if items might be sold. Coordinate with PNP for recovery operations.\n\n"
            "📋 **Legal Basis:** Revised Penal Code (RPC), Articles 308–312 — Theft; "
            "Articles 293–302 — Robbery; "
            "RA 7160, Sections 399–422 — KP jurisdiction for minor disputes"
        ),
    },
    {
        "triggers": {"cybercrime", "online", "hacked", "hack", "scam", "phishing", "identity", "fake", "account", "social media", "facebook", "messenger", "cyber", "libel", "defamation", "libelo", "slander", "threat online", "bullying online", "cyberbullying"},
        "answer": (
            "**Cybercrime and Online Harassment — What to Do**\n\n"
            "**Step 1 — Document everything**\n"
            "Take screenshots of all messages, posts, accounts, or transactions involved. "
            "Do not delete anything — these are your evidence.\n\n"
            "**Step 2 — Report to the Barangay (for cyberbullying)**\n"
            "Online bullying between residents may be reported to the barangay for mediation "
            "under RA 10627 (Anti-Bullying Act). The barangay can issue summons for a settlement.\n\n"
            "**Step 3 — File a complaint with the PNP-ACG or NBI-CCD**\n"
            "For serious cyber offenses (hacking, scam, online libel, identity theft), "
            "file a complaint with the PNP Anti-Cybercrime Group (ACG) or NBI Cybercrime Division. "
            "Bring your screenshots and evidence.\n\n"
            "**Step 4 — Report fake accounts / scam pages**\n"
            "Report to the platform (Facebook, Instagram, etc.) AND to PNP-ACG. "
            "The platform can take down the account; PNP can trace and prosecute the offender.\n\n"
            "**Step 5 — Online libel**\n"
            "If someone posts false statements damaging your reputation online, "
            "you can file online libel under RA 10175. Penalty is higher than traditional libel.\n\n"
            "📋 **Legal Basis:** RA 10175 (Cybercrime Prevention Act of 2012) — "
            "online libel, hacking, identity theft, cyberbullying; "
            "RA 10627 (Anti-Bullying Act) — cyberbullying in schools; "
            "RA 8792 (E-Commerce Act) — electronic fraud"
        ),
    },
    {
        "triggers": {"bullying", "bully", "bullied", "harassment", "hazing", "pang-aapi", "intimidation", "school", "classmate", "student", "teacher"},
        "answer": (
            "**Bullying and Harassment — Legal Remedies**\n\n"
            "**Step 1 — Report to the School (for school bullying)**\n"
            "Report to the school principal or guidance counselor immediately. "
            "Under RA 10627, all schools must have an Anti-Bullying Policy and act within 5 school days.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "For bullying outside school or between community members, report to the barangay. "
            "The barangay can summon both parties for mediation and issue appropriate sanctions.\n\n"
            "**Step 3 — File a complaint at DSWD (for child victims)**\n"
            "If the victim is a minor, the Department of Social Welfare and Development (DSWD) "
            "must be notified. The child may be entitled to protection services.\n\n"
            "**Step 4 — Barangay Protection Order (if physical violence)**\n"
            "If bullying involves physical harm, the Punong Barangay can issue a "
            "Barangay Protection Order (BPO) on the same day.\n\n"
            "**Step 5 — File a criminal case (for serious cases)**\n"
            "Severe bullying (physical injury, hazing, RA 11053) may be filed as criminal cases "
            "in court. Consult the Public Attorney's Office (PAO) for free legal assistance.\n\n"
            "📋 **Legal Basis:** RA 10627 (Anti-Bullying Act of 2013); "
            "RA 11053 (Anti-Hazing Act of 2018); "
            "RA 7610 (Special Protection of Children Against Abuse); "
            "RA 7160, Section 389 — BPO authority"
        ),
    },
    {
        "triggers": {"child", "abuse", "minor", "children", "bata", "neglect", "exploitation", "child labor", "battered child", "sexual abuse", "molest", "rape minor", "trafficking"},
        "answer": (
            "**Child Abuse — Reporting and Protection**\n\n"
            "**Step 1 — Ensure the child's immediate safety**\n"
            "Remove the child from the abusive situation immediately. "
            "Go to the barangay, police station, or nearest DSWD office.\n\n"
            "**Step 2 — Report to the Barangay VAWC Desk**\n"
            "Every barangay has a VAWC Desk that also handles child abuse cases. "
            "The Punong Barangay can issue a Barangay Protection Order (BPO) immediately.\n\n"
            "**Step 3 — Report to DSWD and PNP-WCPD**\n"
            "File a report with the Department of Social Welfare and Development (DSWD) "
            "and the PNP Women and Children Protection Desk (WCPD). "
            "A social worker will be assigned to the case.\n\n"
            "**Step 4 — Medical examination**\n"
            "Bring the child to the nearest government hospital for a medico-legal examination. "
            "The report is critical evidence for the case.\n\n"
            "**Step 5 — File a criminal case**\n"
            "Child abuse is a criminal offense with penalties of 6–40 years imprisonment. "
            "The case is filed in the Family Court. Free legal aid is available through PAO.\n\n"
            "📋 **Legal Basis:** RA 7610 (Special Protection of Children Against Abuse, Exploitation and Discrimination Act); "
            "RA 9262 (Anti-VAWC Act) — child victims; "
            "RA 9208 as amended by RA 10364 — Anti-Trafficking in Persons Act; "
            "RA 7160, Section 389 — BPO authority"
        ),
    },
    {
        "triggers": {"curfew", "minor", "juvenile", "youth", "kabataan", "menor", "out late", "gabi", "youth offender", "youth delinquency", "dilinquent"},
        "answer": (
            "**Curfew for Minors and Juvenile Justice**\n\n"
            "**Curfew Hours (Standard)**\n"
            "Most barangays enforce a curfew for minors below 18 years old: "
            "**10PM–5AM** (varies per local ordinance — some barangays set it at 9PM or 8PM).\n\n"
            "**Step 1 — If a minor is apprehended for curfew violation**\n"
            "The barangay tanod brings the minor to the Barangay Hall — NOT to the police station. "
            "Parents or guardians are immediately notified.\n\n"
            "**Step 2 — Parent/guardian accountability**\n"
            "Parents or guardians may be summoned and fined under local ordinance "
            "for repeated curfew violations by their child.\n\n"
            "**Step 3 — Children in Conflict with the Law (CICL)**\n"
            "Minors who commit offenses are handled under RA 9344 — they cannot be imprisoned "
            "like adults. They undergo intervention, diversion, and rehabilitation programs.\n\n"
            "**Step 4 — Barangay Intervention Program**\n"
            "For first-time minor offenders (minor offenses), the barangay handles the case "
            "through a Diversion Program without going to court.\n\n"
            "**Step 5 — Court referral (for serious offenses)**\n"
            "For serious crimes committed by minors aged 15–18, the case is referred to "
            "the Family Court. Minors below 15 are exempt from criminal liability.\n\n"
            "📋 **Legal Basis:** RA 9344 (Juvenile Justice and Welfare Act of 2006) as amended by RA 10630; "
            "Local Government Anti-Curfew Ordinances under RA 7160"
        ),
    },
    {
        "triggers": {"estafa", "fraud", "scam", "swindling", "deceive", "deceived", "fake", "swindled", "panloloko", "daya", "lokohin", "investment", "pyramiding", "money lost"},
        "answer": (
            "**Estafa / Fraud / Swindling — What to Do**\n\n"
            "**Step 1 — Document the fraud**\n"
            "Gather all evidence: receipts, contracts, text messages, screenshots, bank transfers, "
            "and names/contact details of the suspect.\n\n"
            "**Step 2 — Barangay mediation (for small amounts, known parties)**\n"
            "If the suspect is a neighbor or known person, you may file a complaint at the barangay. "
            "The Lupon can summon both parties to attempt settlement and recovery of money.\n\n"
            "**Step 3 — File a complaint at the prosecutor's office**\n"
            "For larger amounts or if mediation fails, file an Affidavit-Complaint at the "
            "City/Provincial Prosecutor's Office. Bring all documentary evidence.\n\n"
            "**Step 4 — File a police report**\n"
            "Report to the PNP. For online fraud (scam via social media), "
            "also report to the PNP Anti-Cybercrime Group (ACG).\n\n"
            "**Step 5 — Small Claims Court (for money recovery)**\n"
            "For amounts up to ₱400,000, file a Small Claims case in the Municipal Trial Court — "
            "no lawyer required, fast resolution.\n\n"
            "📋 **Legal Basis:** Revised Penal Code (RPC), Articles 315–318 — Estafa and Other Deceits; "
            "RA 10175 (Cybercrime Prevention Act) — online fraud; "
            "A.M. No. 08-8-7-SC — Rule of Procedure for Small Claims"
        ),
    },
    {
        "triggers": {"garbage", "waste", "littering", "dumping", "basura", "environment", "pollution", "dirty", "sanitation", "segregation", "ecology", "trash", "illegal dumping"},
        "answer": (
            "**Garbage, Waste, and Environmental Violations**\n\n"
            "**Step 1 — Report to the Barangay**\n"
            "Report illegal dumping, littering, or unsanitary conditions at the Barangay Hall. "
            "The barangay is the frontline enforcer of solid waste management laws.\n\n"
            "**Step 2 — Barangay enforcement**\n"
            "The Punong Barangay can issue notices of violation and impose fines for littering "
            "and improper garbage disposal under local ordinances.\n\n"
            "**Step 3 — Waste segregation compliance**\n"
            "Households are required to segregate waste: biodegradable, non-biodegradable, "
            "and special/hazardous waste. Non-compliance is subject to barangay fines.\n\n"
            "**Step 4 — Report to City Environment Office**\n"
            "For large-scale illegal dumping or industrial pollution, report to the "
            "City/Municipal Environment and Natural Resources Office (CENRO) or DENR.\n\n"
            "**Step 5 — File a complaint**\n"
            "If the barangay fails to act, escalate to the City/Municipal Mayor's Office "
            "or the Environmental Management Bureau (EMB) under DENR.\n\n"
            "📋 **Legal Basis:** RA 9003 (Ecological Solid Waste Management Act of 2000); "
            "RA 8749 (Philippine Clean Air Act); "
            "RA 9275 (Philippine Clean Water Act); "
            "RA 7160, Section 389 — barangay environmental enforcement"
        ),
    },
    {
        "triggers": {"smoking", "cigarette", "vape", "smoke", "tobacco", "sigarilyo", "usok", "e-cigarette", "liquor", "alcohol", "drinking", "public drinking", "drunk"},
        "answer": (
            "**Anti-Smoking and Liquor Regulations at the Barangay Level**\n\n"
            "**Anti-Smoking Rules:**\n\n"
            "**Step 1 — Designated Smoking Areas**\n"
            "Smoking is prohibited in all public places: barangay halls, markets, schools, "
            "hospitals, public transport, restaurants, and government offices.\n\n"
            "**Step 2 — Report violations**\n"
            "Report smokers in prohibited areas to the barangay. "
            "Fines range from ₱500–₱10,000 for individuals and ₱5,000–₱50,000 for establishments.\n\n"
            "**Step 3 — Vape/E-cigarette regulations**\n"
            "Vaping is prohibited in the same places as smoking under RA 11900 (Vape Law). "
            "Sale to minors under 21 is prohibited.\n\n"
            "**Anti-Liquor/Drinking Rules:**\n\n"
            "**Step 4 — Public drinking**\n"
            "Most barangays prohibit drinking in public places (streets, basketball courts) "
            "especially late at night. Violators are subject to fines or temporary detention.\n\n"
            "**Step 5 — Drunk and disorderly conduct**\n"
            "Persons who are drunk and causing disturbance can be taken into custody by "
            "barangay tanods until sober, then turned over to police if necessary.\n\n"
            "📋 **Legal Basis:** RA 9211 (Tobacco Regulation Act of 2003); "
            "RA 11900 (Vaporized Nicotine and Non-Nicotine Products Regulation Act of 2022); "
            "RA 10586 (Anti-Drunk and Drugged Driving Act); "
            "Local Anti-Liquor Ordinances under RA 7160"
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
    {
        "triggers": {"eviction", "ejectment", "rent", "tenant", "landlord", "renter", "lease", "lessor", "lessee", "upa", "nangungupahan", "panginoong", "paupahan", "renta", "usura", "evict"},
        "answer": (
            "**Eviction and Tenant Rights — What You Need to Know**\n\n"
            "**Step 1 — Know your rights as a tenant**\n"
            "A landlord cannot forcibly eject a tenant without a court order. "
            "Padlocking, cutting utilities, or removing belongings are ILLEGAL even if rent is unpaid.\n\n"
            "**Step 2 — Report illegal eviction to the Barangay**\n"
            "If your landlord is harassing or illegally evicting you, report to the Barangay Hall. "
            "The barangay can summon both parties for mediation and issue a protection notice.\n\n"
            "**Step 3 — Rent Control protection**\n"
            "For monthly rent of ₱10,000 or below (Metro Manila) or ₱5,000 or below (provincial), "
            "the landlord cannot increase rent by more than 2% per year per RA 9653.\n\n"
            "**Step 4 — Legal eviction process**\n"
            "A landlord must file an ejectment case in the Municipal Trial Court. "
            "You have the right to respond and present your case. The process takes months — "
            "you cannot be removed immediately.\n\n"
            "**Step 5 — Barangay mediation first**\n"
            "Before going to court, both parties must undergo barangay mediation (KP process) "
            "and receive a Certificate to File Action (CFA) first.\n\n"
            "📋 **Legal Basis:** RA 9653 (Rent Control Act of 2009); "
            "Rules on Summary Procedure — Ejectment cases; "
            "RA 7160, Sections 399–422 — KP mandatory mediation"
        ),
    },
    {
        "triggers": {"labor", "employee", "employer", "dismissal", "fired", "terminated", "work", "wage", "salary", "overtime", "holiday pay", "separation pay", "illegal dismissal", "dole", "trabaho", "sweldo", "tanggal", "tinanggal", "alis trabaho"},
        "answer": (
            "**Labor Disputes and Worker Rights**\n\n"
            "**Step 1 — Barangay jurisdiction for labor**\n"
            "The barangay handles labor disputes ONLY between household employers and kasambahay (domestic workers). "
            "For regular employment, the Department of Labor and Employment (DOLE) has jurisdiction.\n\n"
            "**Step 2 — File at DOLE (for regular workers)**\n"
            "Go to the nearest DOLE Regional/Field Office. File a complaint for illegal dismissal, "
            "unpaid wages, overtime, or 13th month pay. DOLE mediation (SEnA) is FREE.\n\n"
            "**Step 3 — Single Entry Approach (SEnA)**\n"
            "DOLE's SEnA program mediates labor disputes within 30 days. "
            "Bring employment contract, payslips, and any written communications.\n\n"
            "**Step 4 — National Labor Relations Commission (NLRC)**\n"
            "If SEnA fails, file a formal case at the NLRC. "
            "For illegal dismissal: you may receive back wages + separation pay or reinstatement.\n\n"
            "**Step 5 — Minimum wage compliance**\n"
            "Employers must pay at least the regional minimum wage set by the Regional Tripartite "
            "Wages and Productivity Board. Non-compliance is a criminal offense.\n\n"
            "📋 **Legal Basis:** Presidential Decree 442 (Labor Code of the Philippines); "
            "RA 6727 (Wage Rationalization Act); "
            "RA 10361 (Kasambahay Law) — for domestic workers; "
            "DOLE Department Order No. 147-15 — Termination of Employment"
        ),
    },
    {
        "triggers": {"catcall", "catcalling", "harassment", "gender", "sexist", "wolf whistle", "misogyny", "safe spaces", "online harassment", "gender-based", "sexual harassment", "work harassment", "lewd", "manyak", "bastos", "pandiraya"},
        "answer": (
            "**Gender-Based Harassment and Safe Spaces Act**\n\n"
            "**Step 1 — What counts as harassment under RA 11313**\n"
            "- Catcalling, wolf-whistling, lewd comments in public\n"
            "- Unwanted sexual advances, touching, or gestures\n"
            "- Online sexual harassment (sending lewd images, threats)\n"
            "- Gender-based discrimination in schools, workplaces, and public spaces\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "The barangay is the first responder for street-level harassment. "
            "The Punong Barangay can issue a Barangay Protection Order (BPO) on the same day.\n\n"
            "**Step 3 — File a complaint**\n"
            "File a written complaint at the barangay or nearest PNP station. "
            "Bring any evidence: videos, screenshots, witness names.\n\n"
            "**Step 4 — Penalties**\n"
            "First offense: 1–10 days imprisonment OR ₱1,000–₱10,000 fine. "
            "Repeat offenders and aggravated cases face higher penalties.\n\n"
            "**Step 5 — Workplace harassment**\n"
            "For harassment in the workplace, file with the employer's HR AND the Civil Service "
            "Commission (for government) or DOLE (for private sector). RA 11313 mandates all "
            "workplaces to have a Committee on Decorum and Investigation (CODI).\n\n"
            "📋 **Legal Basis:** RA 11313 (Safe Spaces Act / Bawal Bastos Law of 2019); "
            "RA 7877 (Anti-Sexual Harassment Act of 1995) — workplace/school harassment; "
            "RA 9262 (Anti-VAWC) — gender-based violence"
        ),
    },
    {
        "triggers": {"carnapping", "car", "vehicle", "motorcycle", "stolen vehicle", "carjack", "carjacking", "motor", "kotse", "motor", "sasakyan", "ninakaw na sasakyan"},
        "answer": (
            "**Carnapping and Vehicle Theft — What to Do**\n\n"
            "**Step 1 — Report immediately to PNP**\n"
            "Call 911 or go directly to the nearest PNP station. "
            "Report the exact time, place, vehicle description, plate number, and conduction sticker number. "
            "Time is critical for recovery.\n\n"
            "**Step 2 — File a Barangay Blotter**\n"
            "Also file a blotter at the barangay where the carnapping occurred for documentation.\n\n"
            "**Step 3 — Report to LTO**\n"
            "Report to the Land Transportation Office (LTO) to flag the vehicle as stolen. "
            "This prevents the thief from re-registering the vehicle.\n\n"
            "**Step 4 — Report to your insurance company**\n"
            "If the vehicle is insured, notify your insurance company within 24–48 hours. "
            "Bring the police report and blotter as requirements for the claim.\n\n"
            "**Step 5 — Penalties for carnapping**\n"
            "Carnapping carries 20–30 years imprisonment. If the owner or driver is killed, "
            "the penalty is reclusion perpetua (life imprisonment).\n\n"
            "📋 **Legal Basis:** RA 10883 (New Anti-Carnapping Act of 2016); "
            "Revised Penal Code, Articles 308–312 — Theft (for non-motor vehicles); "
            "RA 4136 (Land Transportation and Traffic Code)"
        ),
    },
    {
        "triggers": {"kasambahay", "domestic worker", "house helper", "maid", "helper", "househelp", "katulong", "yaya", "household worker", "employer kasambahay"},
        "answer": (
            "**Kasambahay (Domestic Worker) Rights and Obligations**\n\n"
            "**Rights of the Kasambahay:**\n\n"
            "**Step 1 — Minimum wage**\n"
            "- NCR: ₱6,000/month minimum\n"
            "- Other chartered cities: ₱5,000/month\n"
            "- Municipalities: ₱2,500/month\n\n"
            "**Step 2 — Mandatory benefits**\n"
            "- SSS, PhilHealth, and Pag-IBIG coverage (employer pays)\n"
            "- 8 hours rest per day, 24 consecutive hours rest per week\n"
            "- 5 days annual service incentive leave\n"
            "- 13th month pay\n\n"
            "**Step 3 — Employment contract required**\n"
            "A written employment contract is mandatory. The barangay must be furnished a copy.\n\n"
            "**Step 4 — Report abuse or non-compliance**\n"
            "For unpaid wages or abuse, report to the barangay (for mediation) or DOLE. "
            "Physical abuse is a criminal offense — report to PNP and file a blotter.\n\n"
            "**Step 5 — Termination rules**\n"
            "Either party may end employment with 5 days notice. "
            "The employer must pay all earned wages and benefits upon termination.\n\n"
            "📋 **Legal Basis:** RA 10361 (Batas Kasambahay / Domestic Workers Act of 2013); "
            "DOLE Department Order No. 5 — implementing rules; "
            "RA 7160, Section 389 — barangay duty to receive employment contracts"
        ),
    },
    {
        "triggers": {"consumer", "overpricing", "price", "defective", "product", "goods", "refund", "warranty", "receipt", "business", "store", "scam store", "price gouging", "DTI", "mamahaling", "dayaan sa tindahan"},
        "answer": (
            "**Consumer Rights and Price Complaints**\n\n"
            "**Step 1 — Document the violation**\n"
            "Keep the receipt, take photos of the product/price tag, and note the store name and address.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "For local stores within the barangay, report price gouging or defective products to "
            "the Punong Barangay, who can mediate between you and the business owner.\n\n"
            "**Step 3 — Report to DTI**\n"
            "File a complaint with the Department of Trade and Industry (DTI): "
            "dti.gov.ph or call 1-384. DTI handles overpricing, defective goods, and misleading ads.\n\n"
            "**Step 4 — Report to the Bureau of Food and Drugs (FDA)**\n"
            "For expired, adulterated, or unsafe food/medicine, report to the Food and Drug Administration (FDA).\n\n"
            "**Step 5 — Refund and warranty rights**\n"
            "You have the right to a refund, replacement, or repair for defective products. "
            "Sellers cannot refuse refunds for products that don't match their description.\n\n"
            "📋 **Legal Basis:** RA 7394 (Consumer Act of the Philippines); "
            "RA 10623 (amended Consumer Act); "
            "RA 7581 (Price Act) — anti-price manipulation; "
            "EO 913 — DTI consumer protection authority"
        ),
    },
    {
        "triggers": {"grave threat", "threats", "threatening", "coercion", "intimidation", "banta", "tinakot", "pananakot", "forced", "blackmail", "extortion", "pangongotong"},
        "answer": (
            "**Grave Threats, Coercion, and Extortion — What to Do**\n\n"
            "**Step 1 — Document the threats**\n"
            "Save all text messages, social media messages, call logs, or recordings. "
            "Write down dates, times, and witnesses if any.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "Report to the Barangay Hall for immediate documentation and blotter entry. "
            "The Punong Barangay can issue a Barangay Protection Order (BPO) if you feel unsafe.\n\n"
            "**Step 3 — File a police report**\n"
            "Go to the nearest PNP station. Grave threats and coercion are criminal offenses "
            "under the Revised Penal Code — the police can take immediate action.\n\n"
            "**Step 4 — Extortion (pangongotong)**\n"
            "If someone is demanding money under threat, do NOT pay. Report immediately to the PNP. "
            "For public officials involved, report to the Ombudsman or NBI.\n\n"
            "**Step 5 — Penalties**\n"
            "Grave threats: 6 months to 6 years imprisonment. "
            "Grave coercion: 6 months to 6 years. "
            "Robbery with intimidation (extortion): 12–20 years.\n\n"
            "📋 **Legal Basis:** Revised Penal Code (RPC), Articles 282–286 — Grave Threats and Coercion; "
            "Article 294 — Robbery with Intimidation; "
            "RA 7160, Section 389 — BPO authority of Punong Barangay"
        ),
    },
    {
        "triggers": {"physical injury", "mauling", "hitting", "punched", "kicked", "beaten", "injured", "wound", "hurt", "sinuntok", "binugbog", "nasaktan", "suntok", "hampas", "physical harm"},
        "answer": (
            "**Physical Injuries — Filing a Complaint**\n\n"
            "**Step 1 — Seek medical attention immediately**\n"
            "Go to the nearest hospital or health center. Request a Medico-Legal Certificate "
            "— this is the most critical piece of evidence for your case.\n\n"
            "**Step 2 — File a Barangay Blotter**\n"
            "Report the incident at the Barangay Hall for official documentation. "
            "The barangay can facilitate mediation if both parties are willing.\n\n"
            "**Step 3 — Classification of physical injuries**\n"
            "- **Slight physical injuries** (heals in 1–9 days): Barangay mediation possible\n"
            "- **Less serious physical injuries** (10–30 days): Barangay or police\n"
            "- **Serious physical injuries** (31+ days, permanent damage): Police + court\n\n"
            "**Step 4 — File a criminal complaint**\n"
            "Bring the medico-legal certificate and blotter to the Prosecutor's Office "
            "to file a formal complaint. For VAWC cases, go to the VAWC Desk.\n\n"
            "**Step 5 — Civil damages**\n"
            "In addition to criminal charges, you can claim civil damages for medical expenses, "
            "lost income, and moral damages.\n\n"
            "📋 **Legal Basis:** Revised Penal Code (RPC), Articles 262–266 — Physical Injuries; "
            "RA 9262 (Anti-VAWC) — if committed by partner or family member; "
            "RA 7160, Sections 399–422 — KP for slight physical injuries"
        ),
    },
    {
        "triggers": {"trespassing", "trespass", "enter", "illegal entry", "break in", "entering property", "unauthorized", "pasok", "pumasok", "nagsalakay", "sinakop"},
        "answer": (
            "**Trespassing and Illegal Entry**\n\n"
            "**Step 1 — Report to the Barangay**\n"
            "Report immediately to the Barangay Hall or Barangay Tanod. "
            "For ongoing trespass, the tanod can respond on-site and remove the intruder.\n\n"
            "**Step 2 — File a Barangay Blotter**\n"
            "Document the incident with names, dates, and witness accounts. "
            "The blotter is important evidence if you escalate to court.\n\n"
            "**Step 3 — Barangay mediation**\n"
            "For neighbor disputes involving boundary encroachment, the Lupon can mediate "
            "and formalize a boundary agreement.\n\n"
            "**Step 4 — File a criminal complaint**\n"
            "Bring the blotter to the Prosecutor's Office. "
            "Trespassing (qualified) carries 6 months to 2 years imprisonment.\n\n"
            "**Step 5 — Secure your property**\n"
            "You may erect fences or barriers on your own property. "
            "However, you CANNOT use excessive force against trespassers — "
            "only reasonable force to protect yourself.\n\n"
            "📋 **Legal Basis:** Revised Penal Code (RPC), Article 280–281 — Trespass to Dwelling; "
            "PD 1529 (Property Registration Decree) — property rights; "
            "RA 7160, Sections 399–422 — KP for boundary disputes"
        ),
    },
    {
        "triggers": {"arson", "fire", "burned", "sinunog", "nagsunog", "nasunog", "sunog", "incendiary", "fire setting"},
        "answer": (
            "**Arson (Intentional Fire-Setting) — What to Do**\n\n"
            "**Step 1 — Ensure safety and call for help**\n"
            "Call 911 or the Bureau of Fire Protection (BFP) immediately. "
            "Evacuate the area. Do not re-enter a burning structure.\n\n"
            "**Step 2 — File a Barangay Blotter**\n"
            "After the fire, file an incident report at the Barangay Hall. "
            "The Punong Barangay will coordinate with BFP and PNP for investigation.\n\n"
            "**Step 3 — BFP fire investigation**\n"
            "The Bureau of Fire Protection (BFP) is mandated to investigate all fires. "
            "Request a copy of the Fire Investigation Report — needed for insurance and legal proceedings.\n\n"
            "**Step 4 — File a criminal case**\n"
            "If arson is suspected, the PNP and Prosecutor's Office handle the criminal case. "
            "Bring the BFP report, photos, and witness accounts.\n\n"
            "**Step 5 — Penalties**\n"
            "Simple arson: 6–12 years imprisonment. "
            "Destructive arson (residential buildings, schools): reclusion perpetua (life) "
            "if someone dies.\n\n"
            "📋 **Legal Basis:** RA 9514 (Revised Fire Code of the Philippines); "
            "Revised Penal Code (RPC), Articles 320–326 — Arson; "
            "RA 7160, Section 389 — barangay fire safety coordination"
        ),
    },
    {
        "triggers": {"fencing", "fence", "anti-fencing", "buy and sell stolen", "receiver stolen goods", "stolen property", "tiangge", "pawnshop stolen", "pagbibili ng ninakaw"},
        "answer": (
            "**Anti-Fencing Law — Buying or Selling Stolen Goods**\n\n"
            "**Step 1 — What is fencing?**\n"
            "Fencing is buying, selling, or possessing goods that you know or should know are stolen. "
            "This includes buying from suspicious sources or at unusually low prices.\n\n"
            "**Step 2 — Report suspected fencing**\n"
            "Report to the barangay or PNP. Provide descriptions of the goods, the seller's identity, "
            "and the location of the transaction.\n\n"
            "**Step 3 — Pawnshops and secondhand dealers**\n"
            "Pawnshops and dealers of secondhand goods are required by law to keep a logbook of "
            "transactions. Non-compliance is a violation. PNP can inspect these establishments.\n\n"
            "**Step 4 — Penalties**\n"
            "Fencing is punishable based on the value of the stolen goods: "
            "minimum 1 year to maximum reclusion temporal (12–20 years) for large amounts.\n\n"
            "**Step 5 — If you unknowingly bought stolen goods**\n"
            "Surrender the goods to the PNP voluntarily. Good faith may be a mitigating factor, "
            "but possession of stolen property still requires explanation.\n\n"
            "📋 **Legal Basis:** PD 1612 (Anti-Fencing Law of 1979); "
            "Revised Penal Code, Article 308 — Theft; "
            "RA 7160, Section 389 — barangay peace and order"
        ),
    },
    {
        "triggers": {"mental health", "depression", "anxiety", "suicidal", "suicide", "mental illness", "psychological", "counseling", "psychiatric", "mental wellness", "stress", "trauma", "ptsd"},
        "answer": (
            "**Mental Health Rights and Support Resources**\n\n"
            "**Step 1 — Emergency mental health crisis**\n"
            "If someone is in immediate danger of self-harm or harming others, call 911 or go to "
            "the nearest government hospital emergency room. The National Center for Mental Health "
            "(NCMH) crisis hotline: **1553** (24/7, free).\n\n"
            "**Step 2 — Barangay mental health support**\n"
            "Barangays are mandated under RA 11036 to have a mental health program and refer "
            "residents to appropriate services. Speak with your Barangay Health Worker (BHW).\n\n"
            "**Step 3 — Free mental health services**\n"
            "Government hospitals and Rural Health Units (RHUs) provide FREE outpatient mental health "
            "services. PhilHealth covers inpatient psychiatric care.\n\n"
            "**Step 4 — Rights of persons with mental illness**\n"
            "- Right to access mental health services without discrimination\n"
            "- Right to confidentiality of mental health records\n"
            "- Cannot be discriminated against in employment, education, or housing\n"
            "- Right to free or affordable medication (RA 11036)\n\n"
            "**Step 5 — Workplace mental health**\n"
            "Employers are required to provide mental health programs for employees. "
            "Discrimination based on mental health condition is prohibited.\n\n"
            "📋 **Legal Basis:** RA 11036 (Philippine Mental Health Act of 2018); "
            "RA 11228 (mandatory PhilHealth coverage); "
            "RA 7277 (Magna Carta for PWDs) — mental disability protection"
        ),
    },
    {
        "triggers": {"inheritance", "heir", "estate", "deceased", "dead", "property death", "will", "testament", "succession", "pamana", "mana", "namatay", "patay", "ari-arian namatay", "extrajudicial"},
        "answer": (
            "**Inheritance and Succession — Your Rights**\n\n"
            "**Step 1 — Who are the legal heirs?**\n"
            "Under Philippine law, legal heirs in order of priority:\n"
            "1. Legitimate children and spouse\n"
            "2. Legitimate parents (if no children)\n"
            "3. Illegitimate children (½ share of legitimate children's share)\n"
            "4. Other relatives (siblings, nephews, nieces)\n\n"
            "**Step 2 — Extrajudicial Settlement (for small estates)**\n"
            "If the estate has no debts and all heirs agree, you can do an Extrajudicial Settlement "
            "through a notarized deed signed by all heirs. Publish in a newspaper once a week for "
            "3 consecutive weeks. File with the BIR and Register of Deeds.\n\n"
            "**Step 3 — Estate tax**\n"
            "Estate tax of **6%** of the net estate must be paid to the BIR within 1 year of death. "
            "Failure to pay results in penalties and surcharges.\n\n"
            "**Step 4 — Barangay's role**\n"
            "The barangay can certify residency and authenticate documents needed for estate proceedings. "
            "For disputes between heirs, the Lupon can mediate.\n\n"
            "**Step 5 — Judicial settlement (for disputes)**\n"
            "If heirs cannot agree, file a petition for judicial settlement in the Regional Trial Court. "
            "Consult the Public Attorney's Office (PAO) for free legal assistance.\n\n"
            "📋 **Legal Basis:** Civil Code of the Philippines, Articles 774–1105 — Succession; "
            "RA 11213 (Tax Amnesty Act) — estate tax amnesty; "
            "Rule 74, Rules of Court — Extrajudicial Settlement"
        ),
    },
    {
        "triggers": {"marriage", "annulment", "separation", "divorce", "kasal", "hiwalay", "annul", "void marriage", "bigamy", "bigamya", "legal separation", "family court", "spouse rights"},
        "answer": (
            "**Marriage, Annulment, and Legal Separation**\n\n"
            "**Important: The Philippines does not have absolute divorce** (except for Muslims under PD 1083).\n\n"
            "**Options for married couples:**\n\n"
            "**Option 1 — Legal Separation**\n"
            "Allows spouses to live separately and divide property, but does NOT allow remarriage. "
            "Filed in Family Court. Grounds include physical violence, drug addiction, infidelity.\n\n"
            "**Option 2 — Annulment**\n"
            "Declares the marriage void from the beginning. Allows remarriage after finality. "
            "Grounds: psychological incapacity (Art. 36), fraud, force, underage marriage.\n\n"
            "**Option 3 — Declaration of Nullity**\n"
            "For void marriages (bigamy, incest, no marriage license). "
            "Simpler to prove than annulment.\n\n"
            "**Step 1 — Consult PAO or a lawyer**\n"
            "Annulment proceedings require a lawyer. The Public Attorney's Office (PAO) provides "
            "free legal assistance for qualified indigent clients.\n\n"
            "**Step 2 — Barangay's role**\n"
            "The barangay issues certifications needed for court proceedings and can mediate "
            "support/custody disputes between separated parents.\n\n"
            "**Step 3 — Child custody and support**\n"
            "Children below 7 years old are generally in the mother's custody. "
            "Child support is mandatory regardless of marital status.\n\n"
            "📋 **Legal Basis:** Family Code of the Philippines (EO 209) — Articles 36, 45, 55; "
            "RA 9048 — Clerical Error Law; "
            "PD 1083 (Code of Muslim Personal Laws) — divorce for Muslims"
        ),
    },
    {
        "triggers": {"data privacy", "personal data", "information leaked", "privacy", "data breach", "hacked account", "personal information", "identity theft", "NPC", "unauthorized access data"},
        "answer": (
            "**Data Privacy Violations — Your Rights**\n\n"
            "**Step 1 — What is a data privacy violation?**\n"
            "- Unauthorized collection or use of your personal information\n"
            "- Data breach exposing your details (name, address, account info)\n"
            "- Sharing your personal data without consent\n"
            "- Identity theft using your personal information\n\n"
            "**Step 2 — Report to the National Privacy Commission (NPC)**\n"
            "File a complaint at privacy.gov.ph or call (02) 8234-2228. "
            "Bring evidence of the violation (screenshots, documents).\n\n"
            "**Step 3 — Report to the organization involved**\n"
            "All organizations handling personal data must have a Data Protection Officer (DPO). "
            "Send a written complaint to the DPO requesting correction or deletion of your data.\n\n"
            "**Step 4 — For government data breaches**\n"
            "Report to the NPC and the Commission on Audit (COA). "
            "Government agencies have stricter obligations under RA 10173.\n\n"
            "**Step 5 — Penalties**\n"
            "Unauthorized processing: 1–3 years imprisonment + ₱500,000–₱2M fine. "
            "Malicious disclosure: 3–5 years + ₱500,000–₱1M fine.\n\n"
            "📋 **Legal Basis:** RA 10173 (Data Privacy Act of 2012); "
            "NPC Circular 16-03 — Security of Personal Data; "
            "RA 10175 (Cybercrime Prevention Act) — computer-related identity theft"
        ),
    },
    {
        "triggers": {"voyeurism", "photo", "video", "secret recording", "upskirt", "recorded without consent", "intimate video", "leaked video", "sex video", "non-consensual", "RA 9995"},
        "answer": (
            "**Anti-Photo and Video Voyeurism Act**\n\n"
            "**Step 1 — What is prohibited**\n"
            "- Taking photos or videos of private parts without consent\n"
            "- Recording intimate acts without knowledge of the subject\n"
            "- Sharing, uploading, or distributing intimate images/videos without consent\n"
            "- This includes leaked sex videos, upskirt photos, and similar acts\n\n"
            "**Step 2 — Preserve evidence**\n"
            "Take screenshots of where the content is posted. Report the content to the platform "
            "(Facebook, Twitter, etc.) for immediate removal.\n\n"
            "**Step 3 — Report to PNP-ACG**\n"
            "File a complaint with the PNP Anti-Cybercrime Group (ACG) if the content was "
            "shared online. Bring all evidence including links and screenshots.\n\n"
            "**Step 4 — File at the Prosecutor's Office**\n"
            "Submit an Affidavit-Complaint with your evidence. The perpetrator can be prosecuted "
            "even if they claim you consented to recording but not sharing.\n\n"
            "**Step 5 — Penalties**\n"
            "3–7 years imprisonment AND ₱100,000–₱500,000 fine. "
            "For uploading/distributing: same penalties per act.\n\n"
            "📋 **Legal Basis:** RA 9995 (Anti-Photo and Video Voyeurism Act of 2009); "
            "RA 10175 (Cybercrime Prevention Act) — if done online; "
            "RA 11313 (Safe Spaces Act) — gender-based online harassment"
        ),
    },
    {
        "triggers": {"ofw", "overseas", "abroad", "worker abroad", "migrant", "deployment", "agency", "illegal recruitment", "recruiter", "placement fee", "OFW family", "remittance", "POEA", "OWWA"},
        "answer": (
            "**OFW and Overseas Employment — Rights and Protection**\n\n"
            "**Step 1 — Verify your recruitment agency**\n"
            "Only use POEA-licensed recruitment agencies. Verify at poea.gov.ph. "
            "Illegal recruiters promise jobs abroad for large fees without proper documentation.\n\n"
            "**Step 2 — Placement fee limits**\n"
            "Placement fees are capped at 1 month salary. Any amount exceeding this is illegal. "
            "Report overcharging to POEA.\n\n"
            "**Step 3 — If stranded or in distress abroad**\n"
            "Contact the nearest Philippine Embassy or Consulate. "
            "OWWA's 24/7 hotline: +632-8891-7601. DFA assistance: (+632) 8651-9400.\n\n"
            "**Step 4 — Illegal recruitment complaint**\n"
            "Report illegal recruiters to POEA or the NBI. "
            "Illegal recruitment is a criminal offense with penalties of 12 years to life imprisonment "
            "if done in large scale.\n\n"
            "**Step 5 — OFW family support at the barangay**\n"
            "The barangay assists OFW families with certifications, referrals to DSWD, and "
            "coordination with OWWA for livelihood programs.\n\n"
            "📋 **Legal Basis:** RA 10022 (Migrant Workers and Overseas Filipinos Act, as amended); "
            "RA 8042 (Migrant Workers Act); "
            "RA 10801 (OWWA Act); "
            "RA 9208 as amended — Anti-Trafficking (labor trafficking)"
        ),
    },
    {
        "triggers": {"free legal", "legal aid", "lawyer free", "pao", "public attorney", "legal assistance", "walang pera abogado", "libre abogado", "legal help", "legal advice free"},
        "answer": (
            "**Free Legal Assistance — Where to Get Help**\n\n"
            "**Option 1 — Public Attorney's Office (PAO)**\n"
            "PAO provides FREE legal representation for indigent clients in criminal, civil, "
            "labor, and administrative cases. Go to the nearest PAO office in your city/municipality.\n"
            "Requirements: proof of indigency (income below ₱14,000/month in NCR, varies per region).\n\n"
            "**Option 2 — Barangay Legal Assistance**\n"
            "The barangay (through the Lupon) provides FREE mediation for qualifying disputes. "
            "This is the fastest and simplest form of legal help.\n\n"
            "**Option 3 — Integrated Bar of the Philippines (IBP)**\n"
            "IBP chapters provide free legal aid clinics. Contact your local IBP chapter.\n\n"
            "**Option 4 — Law school legal aid clinics**\n"
            "Many law schools operate free legal clinics open to the public.\n\n"
            "**Option 5 — NCLA (National Committee on Legal Aid)**\n"
            "Coordinates legal aid services nationwide through the Supreme Court's program.\n\n"
            "**Option 6 — Specific agencies**\n"
            "- DOLE — labor cases\n"
            "- DSWD — family and child welfare cases\n"
            "- CHR — human rights violations\n"
            "- NBI — criminal investigation\n\n"
            "📋 **Legal Basis:** RA 9999 (Free Legal Assistance Act of 2010); "
            "RA 6035 (Public Attorney's Office Law); "
            "Rule XIV, Rules of Court — Legal Aid"
        ),
    },
    {
        "triggers": {"unjust vexation", "oral defamation", "slander", "insult", "cursing", "mura", "pag-insulto", "minura", "nagmura", "defamation", "libel oral", "panlalait"},
        "answer": (
            "**Oral Defamation and Unjust Vexation**\n\n"
            "**Oral Defamation (Slander):**\n\n"
            "**Step 1 — Types of oral defamation**\n"
            "- **Grave oral defamation**: Seriously insulting statements that seriously damage reputation "
            "(e.g., calling someone a criminal, thief, prostitute)\n"
            "- **Slight oral defamation**: Minor insults or offensive language\n\n"
            "**Step 2 — Document the incident**\n"
            "Note the exact words used, date, time, place, and witnesses. "
            "If recorded, save the audio/video.\n\n"
            "**Step 3 — File at the Barangay first**\n"
            "Oral defamation between neighbors requires barangay mediation before court filing. "
            "The barangay can summon the offender and facilitate an apology or settlement.\n\n"
            "**Unjust Vexation:**\n\n"
            "**Step 4 — What is unjust vexation?**\n"
            "Any act that annoys, irritates, or distresses another without legal justification. "
            "Examples: persistent stalking, repeatedly ringing doorbell, blocking a vehicle.\n\n"
            "**Step 5 — Penalties**\n"
            "Grave oral defamation: 6 months + 1 day to 4 years 2 months imprisonment. "
            "Slight oral defamation: 1–30 days imprisonment or fine. "
            "Unjust vexation: fine only (₱200 max under RPC, but courts apply updated amounts).\n\n"
            "📋 **Legal Basis:** Revised Penal Code (RPC), Articles 358–359 — Oral Defamation; "
            "Article 287 — Unjust Vexation; "
            "RA 7160, Sections 399–422 — KP mandatory mediation for these offenses"
        ),
    },
    {
        "triggers": {"election", "vote buying", "voter", "candidate", "campaign", "eleksyon", "boto", "bumoto", "bilangin", "COMELEC", "vote selling", "flying voter", "dagdag bawas"},
        "answer": (
            "**Election Violations — Vote Buying and Voter Rights**\n\n"
            "**Step 1 — Report vote buying/selling**\n"
            "Vote buying (giving money/goods for votes) is a criminal offense. "
            "Report immediately to COMELEC, the barangay, or PNP. You can report anonymously.\n\n"
            "**Step 2 — COMELEC contact**\n"
            "Call the COMELEC action center: 02-525-9296 or email contactus@comelec.gov.ph. "
            "You can also report to PPCRV or Parish-BEC election watchdog.\n\n"
            "**Step 3 — Flying voters / ghost voters**\n"
            "Report to COMELEC with the names of suspected flying voters. "
            "Barangays assist in verifying voter residency for COMELEC audits.\n\n"
            "**Step 4 — Voter rights**\n"
            "Every Filipino citizen, 18 years and above, has the right to vote. "
            "No employer can prevent you from voting. Election Day is a special non-working holiday.\n\n"
            "**Step 5 — Penalties for vote buying**\n"
            "Vote buying AND vote selling: 1–6 years imprisonment + perpetual disqualification "
            "from public office.\n\n"
            "📋 **Legal Basis:** Omnibus Election Code (BP 881), Sections 261–262 — Election offenses; "
            "RA 9369 (Automated Election Law); "
            "RA 8436 — automation of elections"
        ),
    },
    {
        "triggers": {"squatting", "informal settler", "illegal occupant", "relocation", "demolition", "evicted by government", "clearing", "ISF", "slum", "demolisyon", "palipat", "relokasyon"},
        "answer": (
            "**Informal Settlers and Government Relocation Rights**\n\n"
            "**Step 1 — Know your rights as an informal settler**\n"
            "Informal settlers cannot be forcibly evicted without due process. "
            "The government must provide adequate notice (at least 30 days) and relocation assistance.\n\n"
            "**Step 2 — Required before demolition**\n"
            "- Written notice at least 30 days before demolition\n"
            "- A court order (except for danger zones)\n"
            "- Relocation to a site with basic amenities\n"
            "- Financial assistance for moving\n\n"
            "**Step 3 — Report illegal eviction**\n"
            "If government agents demolish without notice or court order, report to the "
            "Commission on Human Rights (CHR) and the Urban Poor Affairs Office (UPAO).\n\n"
            "**Step 4 — Barangay's role**\n"
            "The Punong Barangay must be present during any demolition. "
            "They coordinate with the local government unit (LGU) for relocation assistance.\n\n"
            "**Step 5 — Socialized housing rights**\n"
            "Qualified informal settlers may apply for socialized housing through the National Housing "
            "Authority (NHA) or local government. Priority is given to long-term residents.\n\n"
            "📋 **Legal Basis:** RA 7279 (Urban Development and Housing Act of 1992) — "
            "Sections 28–29, eviction and demolition procedures; "
            "RA 7160, Section 389 — barangay role in demolition; "
            "CHR Resolution A2010-019 — guidelines on forced eviction"
        ),
    },
    {
        "triggers": {"rape", "sexual assault", "molest", "molested", "sexually abused", "rape victim", "rapist", "inabuso", "ginahasa", "nang-rape", "sexual violence", "RA 8353", "rape shield"},
        "answer": (
            "**Rape and Sexual Assault — Immediate Steps and Legal Rights**\n\n"
            "**Step 1 — Prioritize safety and medical care**\n"
            "Go to the nearest hospital IMMEDIATELY. Do not shower, change clothes, or wash up — "
            "physical evidence is critical. Request a medico-legal examination (SANE exam). "
            "This is FREE in all government hospitals.\n\n"
            "**Step 2 — Report to the Barangay VAWC Desk**\n"
            "The barangay VAWC Desk is required to assist rape survivors. "
            "They can accompany you to the hospital and police station, and help you file a report.\n\n"
            "**Step 3 — Report to PNP Women and Children Protection Desk (WCPD)**\n"
            "File a formal complaint at the PNP-WCPD. A female officer must take your statement. "
            "You have the right to privacy — the report is confidential.\n\n"
            "**Step 4 — Rape shield protections**\n"
            "- Your past sexual behavior CANNOT be used against you in court\n"
            "- Your identity will be protected — court records use initials only\n"
            "- You may testify in private (in camera) proceedings\n"
            "- Free legal assistance available through PAO\n\n"
            "**Step 5 — Penalties**\n"
            "Rape: reclusion perpetua (life imprisonment). "
            "If victim is below 12 years old or has disability: death penalty provision (life + max penalties). "
            "Attempted rape: 6–12 years.\n\n"
            "📋 **Legal Basis:** RA 8353 (Anti-Rape Law of 1997); "
            "RA 8505 (Rape Victim Assistance and Protection Act); "
            "RA 11648 (raised age of sexual consent to 16); "
            "RA 9262 (Anti-VAWC) — intimate partner sexual violence"
        ),
    },
    {
        "triggers": {"trafficking", "human trafficking", "recruit", "transport", "harbor", "exploit", "exploitation", "sex trafficking", "labor trafficking", "trafficked", "alipin", "biktima trafficking", "IACAT", "RA 9208"},
        "answer": (
            "**Human Trafficking — Recognition and Reporting**\n\n"
            "**Step 1 — Recognize trafficking**\n"
            "Trafficking signs include:\n"
            "- Promised jobs abroad that turn into forced labor or prostitution\n"
            "- Persons controlled by others, unable to leave or communicate freely\n"
            "- Children found working in bars, massage parlors, or online\n"
            "- Persons with withheld documents (passports, IDs)\n\n"
            "**Step 2 — Report immediately**\n"
            "Call the Inter-Agency Council Against Trafficking (IACAT) hotline: **1343** (24/7, free). "
            "Report to the nearest barangay, PNP, or NBI. You can report anonymously.\n\n"
            "**Step 3 — Barangay's role**\n"
            "Every barangay must have a Violence Against Women and Children (VAWC) desk that also "
            "handles trafficking cases. The Punong Barangay coordinates with DSWD and PNP.\n\n"
            "**Step 4 — Victim support**\n"
            "Trafficking victims are entitled to:\n"
            "- FREE shelter and temporary housing (DSWD recovery centers)\n"
            "- FREE medical, psychological, and legal assistance\n"
            "- Repatriation assistance (for OFW victims)\n"
            "- Immunity from prosecution for acts committed as a result of trafficking\n\n"
            "**Step 5 — Penalties**\n"
            "Trafficking: 20 years to life imprisonment + ₱1M–₱5M fine. "
            "Qualified trafficking (victims are children, done in large scale): life imprisonment.\n\n"
            "📋 **Legal Basis:** RA 9208 as amended by RA 10364 (Expanded Anti-Trafficking in Persons Act); "
            "RA 9775 (Anti-Child Pornography Act); "
            "RA 11930 (Anti-OSAEC Act) — online sexual exploitation"
        ),
    },
    {
        "triggers": {"gambling", "illegal gambling", "jueteng", "talpak", "cara y cruz", "bingo", "mahjong illegal", "sabong illegal", "cockfight", "masugal", "sugal", "manggagamble", "illegal bettor"},
        "answer": (
            "**Illegal Gambling — Reporting and Penalties**\n\n"
            "**Step 1 — What is illegal gambling?**\n"
            "Illegal gambling includes jueteng, masiao, last two, bookmaking, cara y cruz, "
            "and unauthorized cockfighting (outside licensed cockpits or online platforms "
            "not authorized by PAGCOR). Unauthorized online gambling is also illegal.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "Report illegal gambling operations to the Punong Barangay. "
            "The barangay, together with PNP, can raid illegal gambling dens.\n\n"
            "**Step 3 — Report to PNP**\n"
            "File a report at the nearest PNP station. You may report anonymously. "
            "The PNP has a dedicated anti-illegal gambling task force.\n\n"
            "**Step 4 — Legal gambling venues**\n"
            "Only PAGCOR-licensed establishments (casinos, e-Games cafes, PCSO lotteries, "
            "and accredited cockpits) may operate gambling activities legally.\n\n"
            "**Step 5 — Penalties**\n"
            "Operators: 6 months to 6 years imprisonment + ₱3,000–₱6,000 fine. "
            "Bettors: 30 days imprisonment or fine. "
            "For large-scale illegal gambling: up to 12 years + heavier fines.\n\n"
            "📋 **Legal Basis:** PD 1602 (Strengthening Penalties for Illegal Gambling); "
            "RA 9287 (Increasing Penalties for Illegal Numbers Games like Jueteng); "
            "RA 9487 — Philippine Charity Sweepstakes Office (PCSO) Charter; "
            "RA 7160, Section 389 — barangay peace and order"
        ),
    },
    {
        "triggers": {"missing", "missing person", "disappeared", "nawala", "hinahanap", "missing child", "kidnap", "kidnapped", "abducted", "abduction", "FIND", "NCMEC", "wala na", "nawalan"},
        "answer": (
            "**Missing Person — What to Do Immediately**\n\n"
            "**Step 1 — Report to the Barangay immediately**\n"
            "Go to the Barangay Hall right away — there is NO waiting period required. "
            "You do NOT need to wait 24 hours before reporting a missing person. "
            "The barangay will document the report and alert barangay tanods.\n\n"
            "**Step 2 — Report to the PNP**\n"
            "Simultaneously file a missing person report at the nearest PNP station. "
            "Bring a recent photo, full name, age, last known location, and clothing description.\n\n"
            "**Step 3 — For missing children**\n"
            "Contact the PNP Women and Children Protection Desk (WCPD) and the "
            "Inter-Country Adoption Board (ICAB) or DSWD. "
            "For possible kidnapping: call NBI immediately.\n\n"
            "**Step 4 — Alert neighboring barangays**\n"
            "The barangay can coordinate with neighboring barangays and local government to "
            "issue community alerts. Post descriptions on community boards and social media.\n\n"
            "**Step 5 — Kidnapping vs. missing person**\n"
            "If kidnapping is suspected (ransom demanded, threats received), "
            "call PNP Anti-Kidnapping Group (AKG): (02) 8723-0401 immediately. "
            "Do NOT pay ransom without coordinating with authorities.\n\n"
            "📋 **Legal Basis:** RA 9208 (Anti-Trafficking) — missing persons linked to trafficking; "
            "Revised Penal Code, Articles 267–270 — Kidnapping and Serious Illegal Detention; "
            "RA 7610 (Anti-Child Abuse) — missing minors; "
            "RA 7160, Section 389 — barangay peace and order duty"
        ),
    },
    {
        "triggers": {"child support", "support", "maintenance", "alimony", "abandoned child", "abandoned family", "abandonment", "hindi nagbibigay ng suporta", "child custody", "custody", "visitation", "pag-aalalay"},
        "answer": (
            "**Child Support, Custody, and Abandonment**\n\n"
            "**Child Support:**\n\n"
            "**Step 1 — Who is required to provide support?**\n"
            "Both parents — whether married or not — are legally required to support their children. "
            "Support includes food, shelter, education, clothing, and medical care.\n\n"
            "**Step 2 — How much support?**\n"
            "The amount is proportional to the resources of the giver and the needs of the child. "
            "There is no fixed amount — courts determine it based on circumstances.\n\n"
            "**Step 3 — File at the Barangay first**\n"
            "Report non-payment of support to the barangay for mediation. "
            "A barangay-mediated support agreement has the force of a court judgment.\n\n"
            "**Step 4 — File in Family Court**\n"
            "If mediation fails, file a petition for support in the Family Court. "
            "The court can issue a Support Pendente Lite (immediate support while case is ongoing).\n\n"
            "**Child Custody:**\n"
            "Children below 7 years: generally awarded to the mother (unless unfit). "
            "Children above 7: court considers the child's best interest and preference.\n\n"
            "**Abandonment (Criminal):**\n"
            "Abandoning a child under 7 or a family dependent is a criminal offense under the RPC.\n\n"
            "📋 **Legal Basis:** Family Code (EO 209), Articles 194–208 — Support; "
            "Articles 213–216 — Custody; "
            "Revised Penal Code, Article 276 — Abandoning a Minor; "
            "RA 9262 (Anti-VAWC) — economic abuse through non-support"
        ),
    },
    {
        "triggers": {"adoption", "adopt", "adoptee", "foster", "foster care", "ampunin", "inaampon", "inampon", "orphan", "ulila", "NACC", "domestic adoption", "RA 11642"},
        "answer": (
            "**Adoption — Process and Requirements**\n\n"
            "**Step 1 — Who can adopt?**\n"
            "- Filipino citizens, at least 27 years old, at least 16 years older than the adoptee\n"
            "- Husband and wife must jointly adopt (with exceptions)\n"
            "- Must be of good moral character, emotionally and psychologically capable\n"
            "- Must have the means to support the child\n\n"
            "**Step 2 — Domestic Administrative Adoption (new process under RA 11642)**\n"
            "Adoption is now handled by the National Authority for Child Care (NACC) — "
            "NO court appearance required. The process is administrative (faster).\n\n"
            "**Step 3 — Steps to adopt**\n"
            "1. File application at NACC (formerly DSWD)\n"
            "2. Home study conducted by a licensed social worker\n"
            "3. Child matching and placement (6-month trial custody)\n"
            "4. NACC issues the Decree of Adoption\n"
            "5. Register with the Local Civil Registry and PSA\n\n"
            "**Step 4 — Barangay's role**\n"
            "The barangay issues certifications of good moral character and residency "
            "required in the adoption application.\n\n"
            "**Step 5 — Effects of adoption**\n"
            "The adopted child has all rights of a legitimate child including inheritance. "
            "Original birth certificate is sealed; new certificate issued.\n\n"
            "📋 **Legal Basis:** RA 11642 (Domestic Administrative Adoption and Alternative Child Care Act of 2022); "
            "RA 8552 (Domestic Adoption Act of 1998) — still applies for pending cases; "
            "Family Code (EO 209), Articles 183–193"
        ),
    },
    {
        "triggers": {"age discrimination", "old age", "discriminated age", "too old", "ageism", "retirement", "mandatory retirement", "discriminated work", "RA 10911", "anti-age"},
        "answer": (
            "**Anti-Age Discrimination in Employment**\n\n"
            "**Step 1 — What is prohibited?**\n"
            "Employers CANNOT:\n"
            "- Set maximum age limits in job ads or hiring (unless a bona fide requirement)\n"
            "- Refuse to hire or promote someone solely because of age\n"
            "- Force retirement below 60 years old without consent\n"
            "- Discriminate in training, compensation, or conditions of work based on age\n\n"
            "**Step 2 — Mandatory retirement age**\n"
            "The compulsory retirement age is **65 years old** for private sector employees "
            "(optional retirement at 60). "
            "Employers cannot force retirement before 60 without the employee's consent.\n\n"
            "**Step 3 — Report to DOLE**\n"
            "If you experienced age discrimination in hiring or employment, file a complaint "
            "at the nearest DOLE Regional Office. Bring the job ad, rejection letter, or evidence.\n\n"
            "**Step 4 — File a civil case**\n"
            "Victims of age discrimination may file for damages in court. "
            "Free legal assistance available through PAO.\n\n"
            "**Step 5 — Penalties for employers**\n"
            "Fine of ₱50,000–₱500,000 per violation + imprisonment of 3 months to 2 years.\n\n"
            "📋 **Legal Basis:** RA 10911 (Anti-Age Discrimination in Employment Act of 2016); "
            "Labor Code (PD 442), Article 302 — Retirement; "
            "RA 7277 (Magna Carta for PWDs) — disability discrimination"
        ),
    },
    {
        "triggers": {"maternity", "paternity", "leave", "pregnancy", "pregnant", "buntis", "magpapaanak", "maternity leave", "paternity leave", "solo parent leave", "RA 11210"},
        "answer": (
            "**Maternity, Paternity, and Parental Leave Rights**\n\n"
            "**Maternity Leave (RA 11210):**\n"
            "- **105 days** paid maternity leave for live birth (120 days for solo parents)\n"
            "- **60 days** for miscarriage or emergency termination\n"
            "- Available to all female workers — private, government, self-employed, OFW\n"
            "- SSS pays the benefit (computed based on average daily salary credit)\n"
            "- Must notify employer/SSS at least 30 days before expected delivery\n\n"
            "**Paternity Leave (RA 8187):**\n"
            "- **7 days** paid paternity leave for married male employees\n"
            "- Available for first 4 deliveries of the legitimate spouse\n"
            "- Must be availed within 60 days from delivery\n\n"
            "**Solo Parent Leave (RA 8972):**\n"
            "- **7 additional days** per year for solo parents with a Solo Parent ID\n\n"
            "**Step 1 — Notify your employer**\n"
            "Notify in writing as early as possible. Employer CANNOT refuse maternity leave.\n\n"
            "**Step 2 — File SSS/GSIS maternity benefit**\n"
            "Submit SSS Maternity Notification form and required documents to your employer "
            "who forwards to SSS. Self-employed: file directly with SSS.\n\n"
            "**Step 3 — Report violations**\n"
            "Employers who deny maternity/paternity leave face fines + imprisonment. Report to DOLE.\n\n"
            "📋 **Legal Basis:** RA 11210 (105-Day Expanded Maternity Leave Law); "
            "RA 8187 (Paternity Leave Act of 1996); "
            "RA 8972 (Solo Parents' Welfare Act) — solo parent leave"
        ),
    },
    {
        "triggers": {"building permit", "construction", "illegal construction", "no permit", "zoning", "setback", "building violation", "demolish illegal building", "encroach", "nakasali", "walang permit itayo", "DPWH", "building code"},
        "answer": (
            "**Building Permit and Illegal Construction**\n\n"
            "**Step 1 — When is a building permit required?**\n"
            "A building permit is required before constructing, renovating, or demolishing any structure. "
            "Minor repairs (repainting, minor plumbing) generally do not require a permit.\n\n"
            "**Step 2 — Where to get a building permit**\n"
            "Apply at the Office of the Building Official (OBO) in your City or Municipality Hall. "
            "Requirements: lot title/tax declaration, architectural/structural plans, "
            "barangay clearance, and site development plan.\n\n"
            "**Step 3 — Report illegal construction**\n"
            "Report to the barangay. The Punong Barangay can issue a stop-work order for "
            "structures violating zoning ordinances or built without permits.\n\n"
            "**Step 4 — Zoning violations**\n"
            "Each LGU has a Comprehensive Land Use Plan (CLUP) and zoning ordinance. "
            "Building in the wrong zone (e.g., residential area vs. commercial) is a violation "
            "reportable to the Zoning Administrator.\n\n"
            "**Step 5 — Penalties**\n"
            "Constructing without a permit: fine up to ₱20,000 + stop-work order + demolition order. "
            "Repeated violations: criminal prosecution + imprisonment.\n\n"
            "📋 **Legal Basis:** PD 1096 (National Building Code of the Philippines); "
            "RA 9514 (Revised Fire Code) — fire safety compliance; "
            "RA 7160, Sections 447–458 — LGU zoning authority; "
            "RA 7279 — land use and zoning"
        ),
    },
    {
        "triggers": {"agrarian", "farm", "farmer", "tenant farmer", "agricultural", "CARP", "land reform", "DAR", "disturbance compensation", "leaseholder", "magsasaka", "bukid", "lupa bukid", "kasama", "land tenant"},
        "answer": (
            "**Agrarian Reform and Farmer's Rights**\n\n"
            "**Step 1 — What is CARP?**\n"
            "The Comprehensive Agrarian Reform Program (CARP) redistributes agricultural land "
            "to landless farmers and farmworkers. Qualified beneficiaries receive land titles.\n\n"
            "**Step 2 — Who qualifies as an agrarian reform beneficiary?**\n"
            "- Landless farmers and farmworkers who are Filipino citizens\n"
            "- Tillers of private agricultural lands\n"
            "- Cooperative members in agricultural areas\n\n"
            "**Step 3 — Tenant farmer rights**\n"
            "Agricultural lessees (tenants) have security of tenure — they cannot be ejected "
            "without just cause even if the land is sold. They have first right to purchase.\n\n"
            "**Step 4 — Report agrarian disputes**\n"
            "File at the Department of Agrarian Reform (DAR) — Provincial/Municipal Agrarian "
            "Reform Office (PARO/MARO). The DAR handles land disputes, tenancy issues, and "
            "disturbance compensation.\n\n"
            "**Step 5 — Barangay's role**\n"
            "The barangay certifies residency and tenancy for DAR applications and mediates "
            "minor farm boundary disputes through the Lupon.\n\n"
            "📋 **Legal Basis:** RA 6657 as amended by RA 9700 (Comprehensive Agrarian Reform Law); "
            "RA 3844 (Agricultural Land Reform Code) — leasehold tenancy; "
            "RA 7160, Sections 399–422 — KP for agrarian-related minor disputes"
        ),
    },
    {
        "triggers": {"sss", "philhealth", "pagibig", "pag-ibig", "pension", "benefit", "contribution", "social security", "gsis", "retirement benefit", "disability benefit", "death benefit", "housing loan", "sss contribution"},
        "answer": (
            "**SSS, PhilHealth, and Pag-IBIG — Benefits and Disputes**\n\n"
            "**SSS (Social Security System):**\n"
            "- Sickness benefit: 90% of average daily salary for up to 120 days/year\n"
            "- Disability benefit: monthly pension based on credited years of service\n"
            "- Retirement pension: available at age 60 (optional) or 65 (mandatory)\n"
            "- Death/funeral benefit: lump sum + survivorship pension for dependents\n"
            "- Salary/calamity/housing loans available to members\n"
            "- File disputes at nearest SSS branch or my.sss.gov.ph\n\n"
            "**PhilHealth:**\n"
            "- Covers hospitalization, surgeries, maternity, dialysis, chemotherapy\n"
            "- All Filipinos are automatically covered under Universal Health Care (RA 11223)\n"
            "- Report non-remittance of contributions by employers to PhilHealth\n"
            "- Disputes: file at philhealth.gov.ph or nearest PhilHealth office\n\n"
            "**Pag-IBIG (HDMF):**\n"
            "- Housing loans up to ₱6M at low interest rates\n"
            "- Multi-purpose loans (salary loan) for members\n"
            "- Provident savings fund with dividends\n"
            "- File at pagibigfund.gov.ph or nearest branch\n\n"
            "**Report employer non-remittance:**\n"
            "If your employer deducts SSS/PhilHealth/Pag-IBIG from your salary but does not remit, "
            "report to the respective agency AND to DOLE. This is a criminal offense.\n\n"
            "📋 **Legal Basis:** RA 11199 (Social Security Act of 2018); "
            "RA 11223 (Universal Health Care Act); "
            "RA 9679 (Home Development Mutual Fund Law of 2009); "
            "RA 8291 (GSIS Act of 1997) — for government employees"
        ),
    },
    {
        "triggers": {"loan shark", "5-6", "usury", "high interest", "illegal lender", "bombay", "utang mataas", "interest", "overcharging interest", "hindi makapagbayad utang", "debt collector", "harassment creditor"},
        "answer": (
            "**Loan Sharks, Usury, and Illegal Lending**\n\n"
            "**Step 1 — What is usury/illegal lending?**\n"
            "Usury is charging excessively high interest rates beyond what is reasonable and legal. "
            "Common examples: '5-6' lending (20% per day/week), door-to-door lenders charging "
            "100%+ interest per month. Lending without a license from SEC or BSP is illegal.\n\n"
            "**Step 2 — Report to the Barangay**\n"
            "Report illegal lenders operating in your barangay. The barangay can document the "
            "complaint, assist in mediation, and refer to proper authorities.\n\n"
            "**Step 3 — Report to Securities and Exchange Commission (SEC)**\n"
            "File a complaint at sec.gov.ph or call (02) 8818-0921. "
            "SEC regulates lending companies and can shut down unlicensed lenders.\n\n"
            "**Step 4 — Harassment by debt collectors**\n"
            "Debt collectors CANNOT: threaten you, contact your family/employer without consent, "
            "use obscene language, or make false statements. Report harassment to the barangay and PNP.\n\n"
            "**Step 5 — Online lending apps**\n"
            "Illegal online lending apps that access your contacts or post shaming messages "
            "violate the Data Privacy Act (RA 10173) and the SEC's rules. "
            "Report to SEC and the National Privacy Commission (NPC).\n\n"
            "📋 **Legal Basis:** Act No. 2655 (Usury Law) as amended; "
            "RA 9474 (Lending Company Regulation Act of 2007); "
            "BSP Circular 1048 — interest rate ceiling; "
            "RA 10173 (Data Privacy Act) — for online lending app abuses"
        ),
    },
    {
        "triggers": {"child labor", "working child", "minor working", "bata nagtatrabaho", "illegal work minor", "RA 9231", "child worker", "exploited child worker", "hazardous work child"},
        "answer": (
            "**Anti-Child Labor — Rights of Working Children**\n\n"
            "**Step 1 — Minimum working age**\n"
            "Children below **15 years old** cannot be employed in any business or undertaking. "
            "Exception: children below 15 may work ONLY in family undertakings (farm, business) "
            "where the parent is the employer, and work does not interfere with schooling.\n\n"
            "**Step 2 — Children aged 15–17**\n"
            "May work BUT:\n"
            "- Not more than 8 hours per day / 40 hours per week\n"
            "- No night work (10PM–6AM)\n"
            "- Cannot work in hazardous environments (construction, mining, etc.)\n"
            "- Must continue schooling\n\n"
            "**Step 3 — What is hazardous work for children?**\n"
            "Carrying heavy loads, exposure to chemicals, working underground or underwater, "
            "working in bars/clubs, manufacturing with dangerous machinery — all prohibited for minors.\n\n"
            "**Step 4 — Report child labor**\n"
            "Report to the barangay, DOLE, or DSWD. You may report anonymously. "
            "DOLE hotline: 1349. DSWD hotline: 931-8101.\n\n"
            "**Step 5 — Penalties**\n"
            "Employers violating child labor laws: ₱1,000–₱10,000 fine per child + "
            "6 months to 2 years imprisonment.\n\n"
            "📋 **Legal Basis:** RA 9231 (Special Protection of Children Against Child Abuse, "
            "Exploitation and Discrimination Act — Child Labor provisions); "
            "RA 7610, Section 12 — employment of children; "
            "Labor Code (PD 442), Articles 137–139"
        ),
    },
    {
        "triggers": {"online sexual", "OSAEC", "child pornography", "child nude", "child video", "online exploitation child", "RA 9775", "RA 11930", "CSAM", "child sexual abuse material"},
        "answer": (
            "**Online Sexual Exploitation of Children (OSAEC)**\n\n"
            "**Step 1 — What is OSAEC?**\n"
            "OSAEC includes:\n"
            "- Producing, distributing, or possessing child sexual abuse material (CSAM)\n"
            "- Live-streaming sexual abuse of children for online viewers\n"
            "- Grooming children online for sexual purposes\n"
            "- Engaging children in cybersex activities\n\n"
            "**Step 2 — Report immediately — Do NOT share the material**\n"
            "Report to REPORT-IT hotline: **1868** or visit cybercrime.gov.ph. "
            "Also report to PNP-ACG and DSWD immediately.\n\n"
            "**Step 3 — Preserve evidence (safely)**\n"
            "Screenshot URLs and report them to the platform. "
            "Do NOT download or re-share the material — possession alone is a criminal offense.\n\n"
            "**Step 4 — Victim assistance**\n"
            "Victims are entitled to FREE psychological, legal, and social services through DSWD. "
            "Identity of child victims is strictly protected — no names in reports.\n\n"
            "**Step 5 — Penalties**\n"
            "Producing CSAM: 20 years to life imprisonment. "
            "Possession: 12–20 years. Online sale: life imprisonment. "
            "Facilitating (parents/guardians): 12–20 years.\n\n"
            "📋 **Legal Basis:** RA 11930 (Anti-OSAEC and Anti-CSAEM Act of 2022); "
            "RA 9775 (Anti-Child Pornography Act of 2009); "
            "RA 10175 (Cybercrime Prevention Act) — child pornography provisions"
        ),
    },
    {
        "triggers": {"endo", "contractualization", "contractual", "fixed term", "5 months contract", "no regularization", "illegal endo", "labor contracting", "manpower agency", "regularize", "regular employee"},
        "answer": (
            "**Endo and Illegal Contractualization**\n\n"
            "**Step 1 — What is illegal endo?**\n"
            "'Endo' (end of contract) is the practice of repeatedly hiring workers on short-term "
            "contracts (usually 5 months) to prevent them from becoming regular employees "
            "and receiving full benefits. This is ILLEGAL under DOLE regulations.\n\n"
            "**Step 2 — When do you become a regular employee?**\n"
            "After **6 months** of continuous service doing work necessary and desirable to the "
            "business, you are automatically a regular employee — regardless of your contract type.\n\n"
            "**Step 3 — Rights of regular employees**\n"
            "- Security of tenure (cannot be dismissed without just cause)\n"
            "- Full benefits: SSS, PhilHealth, Pag-IBIG, 13th month pay, service incentive leave\n"
            "- Separation pay if retrenched or position abolished\n\n"
            "**Step 4 — Report to DOLE**\n"
            "File a complaint at the nearest DOLE Regional/Field Office. "
            "DOLE conducts labor inspections and can order regularization. DOLE hotline: **1349**.\n\n"
            "**Step 5 — File at NLRC for illegal dismissal**\n"
            "If you were terminated to avoid regularization, file an illegal dismissal case at the NLRC. "
            "You may be entitled to back wages and reinstatement.\n\n"
            "📋 **Legal Basis:** Labor Code (PD 442), Article 295 — Regular and Casual Employment; "
            "DOLE Department Order No. 174-17 — Rules on Contracting and Subcontracting; "
            "DOLE Advisory No. 01-17 — guidelines on employment status"
        ),
    },
    {
        "triggers": {"business permit", "business license", "mayor's permit", "DTI registration", "sole proprietorship", "barangay business", "business clearance", "business registration", "negosyo", "tindahan permit", "store permit"},
        "answer": (
            "**Business Permit and Registration**\n\n"
            "**Step 1 — Register your business name (DTI)**\n"
            "For sole proprietorships, register your business name with the DTI. "
            "Do this online at negosyo.dti.gov.ph or at the nearest DTI office. Fee: ₱200–₱2,000.\n\n"
            "**Step 2 — Get a Barangay Business Clearance**\n"
            "Go to your Barangay Hall and apply for a Barangay Business Clearance. "
            "Requirements: DTI registration, valid ID, proof of location. "
            "Fee varies per barangay (usually ₱500–₱2,000). This is renewed annually.\n\n"
            "**Step 3 — Get a Mayor's Permit (Business License)**\n"
            "Apply at the City/Municipal Business Permits and Licensing Office (BPLO). "
            "Requirements: Barangay Clearance, DTI registration, BIR registration, "
            "lease contract or proof of ownership, and fire safety inspection certificate.\n\n"
            "**Step 4 — Register with BIR**\n"
            "Register with the Bureau of Internal Revenue (BIR) for tax compliance. "
            "Get a Certificate of Registration (COR) and official receipts (OR).\n\n"
            "**Step 5 — Annual renewal**\n"
            "Renew your Barangay Clearance and Mayor's Permit annually (January of each year). "
            "Late renewal incurs surcharges.\n\n"
            "📋 **Legal Basis:** RA 7160 (Local Government Code), Section 444 — "
            "Mayor's permit authority; "
            "RA 3883 (Business Name Law) as amended by RA 9178; "
            "NIRC (National Internal Revenue Code) — BIR registration; "
            "RA 11032 (Ease of Doing Business Act)"
        ),
    },
    {
        "triggers": {"disaster", "calamity", "typhoon", "flood", "earthquake", "emergency", "relief", "evacuation", "NDRRMC", "LGU relief", "sakuna", "lindol", "bagyo", "baha", "evacuate", "evacuation center"},
        "answer": (
            "**Disaster Relief and Emergency Preparedness**\n\n"
            "**Step 1 — Evacuation**\n"
            "Follow barangay official evacuation orders immediately. "
            "The Punong Barangay has authority to order mandatory evacuation in danger zones. "
            "Go to your designated barangay evacuation center.\n\n"
            "**Step 2 — Barangay Disaster Risk Reduction and Management Council (BDRRMC)**\n"
            "Every barangay has a BDRRMC that coordinates disaster response. "
            "Contact the barangay tanod or BDRRMC during emergencies.\n\n"
            "**Step 3 — Relief goods and assistance**\n"
            "Disaster survivors are entitled to:\n"
            "- Emergency food, water, and shelter\n"
            "- Medical assistance from the barangay health center and DOH\n"
            "- Emergency cash assistance from DSWD (up to ₱15,000 for major disasters)\n"
            "- Housing assistance from NHA and DSWD for totally damaged homes\n\n"
            "**Step 4 — Report disaster-related corruption**\n"
            "If relief goods are withheld or misappropriated, report to the COA, Ombudsman, "
            "or directly to DSWD. Corruption during disasters has higher penalties.\n\n"
            "**Step 5 — Post-disaster legal remedies**\n"
            "For property damaged by neighbors' negligence during a disaster, "
            "file at the barangay for mediation. Insurance claims for damage follow policy terms.\n\n"
            "📋 **Legal Basis:** RA 10121 (Philippine Disaster Risk Reduction and Management Act of 2010); "
            "RA 7160, Section 389 — Punong Barangay emergency powers; "
            "RA 10869 — Sagana at Ligtas na Tubig Act"
        ),
    },
    {
        "triggers": {"illegal logging", "wildlife", "poaching", "endangered species", "cutting trees", "illegal fishing", "dynamite fishing", "cyanide fishing", "pagputol ng puno", "pangingisda ilegal", "DENR", "BFAR"},
        "answer": (
            "**Illegal Logging, Wildlife, and Fishing Violations**\n\n"
            "**Illegal Logging:**\n\n"
            "**Step 1 — Report illegal logging**\n"
            "Report to the DENR (Department of Environment and Natural Resources), barangay, "
            "or PNP. You can call the DENR hotline: 1-800-10-DENR-123 (1-800-10-3367-123).\n\n"
            "**Step 2 — Penalties for illegal logging**\n"
            "Imprisonment of 12–20 years + fines + confiscation of equipment and products.\n\n"
            "**Illegal Wildlife:**\n\n"
            "**Step 3 — Report illegal wildlife trade**\n"
            "Report to DENR-Biodiversity Management Bureau. Killing, collecting, or trading "
            "endangered species (eagles, turtles, monkeys) is strictly prohibited.\n\n"
            "**Illegal Fishing:**\n\n"
            "**Step 4 — Report illegal fishing**\n"
            "Report to BFAR (Bureau of Fisheries and Aquatic Resources) or the PNP Maritime Group. "
            "Hotline: (02) 8332-4661.\n\n"
            "**Step 5 — What is prohibited**\n"
            "- Dynamite/blast fishing: 20 years imprisonment\n"
            "- Cyanide fishing: 8–20 years\n"
            "- Fishing in municipal waters without license: fines + confiscation\n"
            "- Use of fine-mesh nets (baby fish): fines + license cancellation\n\n"
            "📋 **Legal Basis:** RA 9175 (Chainsaw Act of 2002) — illegal logging; "
            "RA 9147 (Wildlife Resources Conservation and Protection Act); "
            "RA 10654 (Philippine Fisheries Code of 2015); "
            "PD 705 (Revised Forestry Code)"
        ),
    },
    {
        "triggers": {"electricity theft", "meralco", "power", "electric", "kuryente", "illegal connection", "jumper", "water theft", "water pilferage", "tubig", "illegal tap", "Manila Water", "Maynilad"},
        "answer": (
            "**Electricity and Water Theft / Pilferage**\n\n"
            "**Electricity Theft:**\n\n"
            "**Step 1 — What is electricity pilferage?**\n"
            "- Illegal connection (jumper) to power lines without a meter\n"
            "- Tampering with electric meters to reduce readings\n"
            "- Using unregistered appliances that bypass billing\n\n"
            "**Step 2 — Consequences**\n"
            "Electric company may immediately disconnect supply and assess differential billing "
            "(estimated unbilled consumption) going back up to 5 years.\n\n"
            "**Step 3 — Report electricity theft**\n"
            "Report to Meralco (in areas served) or your local electric cooperative. "
            "You can report anonymously to prevent electricity theft that drives up costs for all.\n\n"
            "**Water Pilferage:**\n\n"
            "**Step 4 — What is water pilferage?**\n"
            "Illegal connection to water mains, tampering with water meters, or unauthorized use "
            "of fire hydrants are all punishable offenses.\n\n"
            "**Step 5 — Penalties**\n"
            "Electricity theft: 1–12 years imprisonment + payment of differential billing + fines. "
            "Water pilferage: fines + imprisonment + civil liability for water consumed.\n\n"
            "📋 **Legal Basis:** RA 7832 (Anti-Electricity and Electric Transmission Lines/Materials "
            "Pilferage Act of 1994); "
            "RA 8041 (National Water Crisis Act) — water pilferage provisions; "
            "RA 9136 (Electric Power Industry Reform Act — EPIRA)"
        ),
    },
    {
        "triggers": {"anti-hazing", "hazing", "initiation rites", "fraternity", "sorority", "organization initiation", "padyak", "paddling", "physical initiation", "RA 11053"},
        "answer": (
            "**Anti-Hazing Law — Rights of Students and Members**\n\n"
            "**Step 1 — What is hazing?**\n"
            "Hazing is any initiation rite or practice that causes physical, psychological, "
            "or emotional suffering as a prerequisite for membership in any group, "
            "organization, military, or educational institution.\n\n"
            "**Step 2 — All hazing is now regulated**\n"
            "Under RA 11053, hazing is PROHIBITED unless:\n"
            "- Prior written notice is given to the school authority\n"
            "- A school representative is present\n"
            "- No physical harm is inflicted\n"
            "Physical hazing (paddling, hitting, forced exercise) is ALWAYS prohibited.\n\n"
            "**Step 3 — Report to the school and barangay**\n"
            "Report immediately to the school principal/president AND to the barangay where the "
            "initiation occurred. File a blotter. The barangay will coordinate with PNP.\n\n"
            "**Step 4 — Report to PNP and file a case**\n"
            "Hazing that results in injury or death is a criminal offense. "
            "All participants — planners, principals, participants who did not prevent it — are liable.\n\n"
            "**Step 5 — Penalties**\n"
            "If victim suffers injury: 6–12 years. "
            "If victim dies: reclusion perpetua (life) for all responsible parties. "
            "School officials who knew and failed to act: also liable.\n\n"
            "📋 **Legal Basis:** RA 11053 (Anti-Hazing Act of 2018); "
            "RA 8049 (Anti-Hazing Law of 1995) — superseded by RA 11053; "
            "RA 7610 — child abuse provisions for minor victims"
        ),
    },
    {
        "triggers": {"rights of accused", "arrested", "detained", "arrest", "warrant", "warrantless arrest", "miranda rights", "inquest", "preliminary investigation", "bail", "detained rights", "naaresto", "nakulong"},
        "answer": (
            "**Rights of the Accused and Arrested Persons**\n\n"
            "**Your rights upon arrest (Miranda Rights):**\n\n"
            "**Step 1 — Right to be informed**\n"
            "You have the right to be told:\n"
            "- The reason for your arrest\n"
            "- Your right to remain silent\n"
            "- Your right to a lawyer (even if you cannot afford one)\n\n"
            "**Step 2 — Right to remain silent**\n"
            "You do NOT have to answer any questions. Say: "
            "'I invoke my right to remain silent and to counsel.' "
            "Anything you say can be used against you in court.\n\n"
            "**Step 3 — Right to a lawyer**\n"
            "You have the right to a lawyer at ALL stages of investigation. "
            "If you cannot afford one, the Public Attorney's Office (PAO) will provide one for free.\n\n"
            "**Step 4 — Warrantless arrest — when is it valid?**\n"
            "Police can arrest without a warrant only if:\n"
            "- You are caught in the act (in flagrante delicto)\n"
            "- Hot pursuit of a crime just committed\n"
            "- Escaped prisoner\n"
            "Otherwise, a valid court-issued warrant is required.\n\n"
            "**Step 5 — Detention limits**\n"
            "Without a warrant: 12 hours (light offense), 18 hours (less grave), 36 hours (grave offense). "
            "After that, charges must be filed or you must be released. "
            "File a complaint for arbitrary detention at the Ombudsman if rights are violated.\n\n"
            "📋 **Legal Basis:** 1987 Philippine Constitution, Article III (Bill of Rights) — "
            "Sections 12–14; "
            "Rules of Court, Rule 113 — Arrest; "
            "RA 7438 (Rights of Persons Arrested, Detained or Under Custodial Investigation)"
        ),
    },
    {
        "triggers": {
            "payment", "fee", "fees", "cost", "costs", "charge", "charges",
            "libre", "free", "magkano", "singil", "bayaran",
        },
        "answer": (
            "**Barangay Services — Are There Fees?**\n\n"
            "Good news: most barangay legal aid services are **FREE of charge**.\n\n"
            "**No fees for:**\n"
            "- Filing a complaint or blotter at the Barangay Hall\n"
            "- Barangay mediation and conciliation (KP process)\n"
            "- Summons issued to the other party\n"
            "- Lupon hearings and settlement sessions\n"
            "- Barangay Clearance (some barangays charge a minimal admin fee of ₱50–₱100)\n\n"
            "**If the case goes to court**, filing fees apply under the Rules of Court. "
            "However, indigent litigants may avail of free legal aid from the Public Attorney's Office (PAO).\n\n"
            "**Tip:** If anyone at the barangay asks for an unofficial payment or 'lagay' to process "
            "your complaint, you have the right to refuse and report it as corruption.\n\n"
            "📋 **Legal Basis:** RA 7160 (Local Government Code), Section 394 — "
            "Barangay officials must render service without any fees or charges for KP proceedings; "
            "RA 9999 — Free Legal Assistance Act"
        ),
    },
]


def _topic_from_previous_answer(assistant_text: str) -> Optional[dict]:
    """
    Given a previous assistant response, figure out which _LEGAL_TOPICS entry
    it came from by scoring how many trigger words appear in the answer text.
    Returns the topic dict (with 'answer') or None.
    """
    answer_words = set(re.sub(r"[^\w\s]", "", assistant_text.lower()).split())
    best_topic = None
    best_score = 0
    for topic in _LEGAL_TOPICS:
        overlap = len(answer_words & topic["triggers"])
        if overlap > best_score:
            best_score = overlap
            best_topic = topic
    # Require at least 2 trigger words in the answer to be confident
    return best_topic if best_score >= 2 else None


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

def get_instant_answer(message: str, history: list | None = None) -> Optional[str]:
    """
    Returns an instant local answer ONLY for greetings and vague queries.
    Legal topic and FAQ answers are NOT returned here — they go to the model as context.
    """
    text = message.strip()
    expanded = _expand_tagalog(text)
    if _is_greeting(text):
        logger.info(f"[CHATBOT] Greeting detected: {text[:40]}")
        return _GREETING_RESPONSE
    if _is_vague(text) and _is_vague(expanded):
        logger.info(f"[CHATBOT] Vague query, asking for clarification: {text[:60]}")
        return _CLARIFICATION_RESPONSE
    return None


def get_legal_context(message: str, history: list | None = None) -> Optional[str]:
    """
    Returns the best matching legal topic or FAQ answer as RAG context for the model.
    Does NOT return this as a final answer — the model uses it to generate a response.
    """
    text = message.strip()
    tl = _is_tagalog(text)
    expanded = _expand_tagalog(text)
    enriched = _enrich_with_history(expanded, history or [])

    # Short follow-up detection: ≤8 words and conversation history exists.
    # For these, try the original query FIRST (before history-enriched) so that
    # the follow-up's own intent wins over previous topic keywords.
    # Then, if the query has no direct topic match of its own, stay in the
    # previous topic dynamically (inferred from the last assistant message).
    is_short_followup = len(text.split()) <= 8 and bool(history)

    if is_short_followup:
        # 1. Try direct match on original / expanded text (follow-up's own intent)
        topic_hit = (
            _match_legal_topic(text, tagalog=tl)
            or _match_legal_topic(expanded, tagalog=tl)
        )

        if not topic_hit:
            # 2. No direct match — dynamically infer the active topic from the
            #    last assistant message and stay in it.
            last_assistant = next(
                (h.get("content", "") for h in reversed(history or [])
                 if h.get("role") in ("assistant", "model")),
                None,
            )
            if last_assistant:
                prev_topic = _topic_from_previous_answer(last_assistant)
                if prev_topic:
                    logger.info(
                        f"[CHATBOT] Follow-up detected — staying in topic for: {text[:50]}"
                    )
                    topic_hit = (
                        prev_topic.get("answer_tl") if tl else None
                    ) or prev_topic["answer"]

        if not topic_hit:
            # 3. Last resort: try enriched
            topic_hit = _match_legal_topic(enriched, tagalog=tl)
    else:
        topic_hit = (
            _match_legal_topic(enriched, tagalog=tl)
            or _match_legal_topic(expanded, tagalog=tl)
            or _match_legal_topic(text, tagalog=tl)
        )

    if topic_hit:
        logger.info(f"[CHATBOT] Legal context retrieved for: {text[:60]}")
        return topic_hit

    faq_hit = _faq_search(enriched) or _faq_search(expanded) or _faq_search(text)
    if faq_hit:
        logger.info(f"[CHATBOT] FAQ context retrieved for: {text[:60]}")
        return faq_hit

    return None


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
