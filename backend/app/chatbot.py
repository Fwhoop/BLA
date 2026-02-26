import os
import re
import json
import logging
from typing import Optional, List, Dict, Tuple
from difflib import SequenceMatcher

logger = logging.getLogger(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LORA_MODEL_DIR = os.path.join(BASE_DIR, "bla_chatbot_model_gemma_lora_project", "full_model")
BASE_MODEL_ID = "google/gemma-3-1b-it"
JSON_FILE = os.path.join(os.path.dirname(BASE_DIR), "barangay_law_flutter.json")

# Concise system prompt for the 1B model — routing is handled in Python
_GEMMA_SYSTEM_PROMPT = (
    "You are the official AI Assistant of the Barangay Web/Mobile Application. "
    "Help residents with barangay services. Be concise, friendly, and action-oriented. "
    "Answer in the same language the user uses (Filipino or English). "
    "Do NOT say you are an AI or mention stored data. Keep answers short and helpful."
)

# ─── Gemma LoRA model (primary for Q&A) ───────────────────────────────────────
model = None
tokenizer = None
model_loaded = False

try:
    from transformers import AutoTokenizer, AutoModelForCausalLM
    from peft import PeftModel
    import torch

    if os.path.exists(LORA_MODEL_DIR):
        logger.info(f"Loading Gemma LoRA tokenizer from {LORA_MODEL_DIR}...")
        tokenizer = AutoTokenizer.from_pretrained(LORA_MODEL_DIR)

        logger.info(f"Loading base model {BASE_MODEL_ID}...")
        base_model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL_ID,
            torch_dtype=torch.float32,
            device_map="auto",
        )

        logger.info("Applying LoRA adapter...")
        model = PeftModel.from_pretrained(base_model, LORA_MODEL_DIR)
        model.eval()
        model_loaded = True
        logger.info("Gemma LoRA model loaded successfully!")
    else:
        logger.warning(f"LoRA model directory not found at {LORA_MODEL_DIR}. Using FAQ fallback.")

except ImportError as e:
    logger.warning(f"ML libraries not available ({e}). Using FAQ fallback.")
except Exception as e:
    logger.error(f"Could not load Gemma LoRA model: {e}. Using FAQ fallback.")


# ─── Intent patterns ──────────────────────────────────────────────────────────
_COMPLAINT_PATS = [
    r'\breklamo\b', r'\bcomplain\b', r'\breport\b', r'\bsumbong\b',
    r'\bviolence\b', r'\bdroga\b', r'\bdrug\b', r'\badik\b',
    r'\bharassment\b', r'\bnoise\b', r'\bdisturbance\b',
    r'\bkapitbahay\b', r'\bireklamo\b', r'\bmagreklamo\b',
    r'\bilegal\b', r'\bstolen\b', r'\bnakaw\b', r'\bbrawl\b',
    r'\bfight\b', r'\bassault\b', r'\bbastusin\b',
    r'file.{0,10}complaint', r'mag.{0,10}file.{0,10}reklamo',
    r'i.{0,5}want.{0,5}report', r'gusto.{0,10}mag.{0,10}reklamo',
    r'\bnag.?aaway\b', r'\bingay\b', r'\bpag.?sumbong\b',
]
_DRUG_PATS = [
    r'\bdrug\b', r'\badik\b', r'\bdroga\b', r'\bshabu\b',
    r'\bpusher\b', r'\billegal.{0,10}drug\b',
]
# Pure action: user wants to REQUEST — no fee/process question in same message
_DOCUMENT_PATS = [
    r'\bkukuha\b', r'\bkumuha\b', r'\bmag.?request\b',
    r'gusto.{0,15}(kumuha|humingi|mag.?request)',
    r'(humingi|kumuha|request).{0,15}(clearance|certificate|certipikasyon)',
    r'i.{0,10}(want|need).{0,10}(clearance|certificate|document)',
    r'\bpag.?request\b',
]
# Separate keyword list used ONLY when no question-pattern fires
_DOCUMENT_TOPIC_PATS = [
    r'\bclearance\b', r'\bcertificate\b', r'\bresidency\b',
    r'\bindigency\b', r'\bgood moral\b', r'\bno income\b',
    r'\bno property\b', r'\blive birth\b', r'\bmarriage\b',
    r'\bdeath.{0,5}cert\b', r'\bsingle status\b',
    r'\bpapel\b', r'\brekuesto\b', r'\bcertipikasyon\b',
    r'request.{0,10}cert', r'need.{0,10}cert',
]
_TRACKING_PATS = [
    r'\bfollow.?up\b', r'\bstatus\b', r'\btracking\b', r'\btrack\b',
    r'\bano na\b', r'\bupdate\b', r'\bnasubmit\b', r'\bnafile\b',
    r'\bnagsumite\b', r'\bmy.{0,10}request\b', r'\bmy.{0,10}complaint\b',
    r'\bpending\b', r'\bsaan na\b', r'\bnasaan.{0,10}request\b',
    r'\bcheck.{0,10}status\b',
]
_SUGGESTION_PATS = [
    r'\bsuggestion\b', r'\bfeedback\b', r'\bpuna\b', r'\bpanukala\b',
    r'\bimprove\b', r'\brecommend\b', r'\bmungkahi\b', r'\bsuggest\b',
]
_GREETING_PATS = [
    r'^(hi|hello|hey|good\s+morning|good\s+afternoon|good\s+evening|'
    r'kumusta|kamusta|musta|hola|yo|sup|greetings?|ola|test|testing|'
    r'magandang\s+\w+)[\s!.?]*$',
]
# Questions about fees, process, requirements → always Q&A (takes priority over document routing)
_QUESTION_PATS = [
    r'\bmagkano\b', r'\bhow much\b', r'\bbayad\b', r'\bfee\b',
    r'\bpaano\b', r'\bhow to\b', r'\bproseso\b', r'\bprocess\b',
    r'\bprocedure\b', r'\brequirement[s]?\b', r'\bgaano\b',
    r'\bhow long\b', r'\bkailan\b.*\b(tapos|ready|abot|dating)\b',
    r'\bsaan\b.*\b(mag.?file|mag.?submit|pumunta|kumuha)\b',
    r'\bwhere\b.*\b(file|submit|get|apply)\b',
    r'\bwhat.{0,10}(need|bring|require)\b',
    r'\bano.{0,10}(kailangan|dala|dokumento|requirements?)\b',
]
# Vague follow-up triggers — short messages referencing "this/that/it"
_VAGUE_WORDS = {
    'magkano', 'how much', 'paano', 'how to', 'kailan', 'when',
    'gaano', 'ito', 'iyon', 'that', 'saan', 'where', 'bakit', 'why',
    'ano', 'what', 'sino', 'who', 'dito', 'doon', 'nito', 'nun',
}
# Topic keywords for context enrichment
_TOPIC_KEYWORDS = {
    'clearance': 'barangay clearance',
    'certificate': 'barangay certificate',
    'residency': 'certificate of residency',
    'indigency': 'certificate of indigency',
    'good moral': 'certificate of good moral character',
    'no income': 'certificate of no income',
    'no property': 'certificate of no property',
    'complaint': 'barangay complaint filing',
    'reklamo': 'barangay reklamo',
    'conciliation': 'barangay conciliation',
    'pangkat': 'pangkat ng tagapagkasundo',
    'lupon': 'lupong tagapamayapa',
    'katarungang': 'Katarungang Pambarangay',
}


_PUNCT_RE = re.compile(r'[^\w\s]')

# Stop words removed before word-overlap scoring
_STOP_WORDS = {
    # Filipino
    'ang', 'ng', 'sa', 'na', 'ay', 'at', 'ni', 'mga', 'ko', 'mo', 'niya',
    'namin', 'natin', 'ninyo', 'nila', 'ba', 'po', 'ho', 'kaya', 'nga',
    'yung', 'ung', 'siya', 'sila', 'kami', 'tayo', 'kayo', 'lang', 'din',
    'rin', 'naman', 'pala', 'kasi', 'pero', 'para', 'kung', 'kapag',
    # English
    'the', 'a', 'an', 'of', 'in', 'is', 'to', 'what', 'how', 'do', 'i',
    'for', 'and', 'or', 'can', 'my', 'be', 'are', 'was', 'were', 'will',
    'with', 'that', 'this', 'it', 'from', 'by', 'if', 'not', 'but', 'as',
    'on', 'at', 'we', 'you', 'they', 'he', 'she', 'have', 'has', 'had',
    'would', 'could', 'should', 'may', 'might', 'about',
}


def _match(text: str, patterns: list) -> bool:
    t = text.lower()
    return any(re.search(p, t) for p in patterns)


def _is_vague(text: str) -> bool:
    """True if message is a short follow-up referencing previous context."""
    words = _PUNCT_RE.sub('', text.lower()).split()
    return len(words) <= 7 and bool(set(words) & _VAGUE_WORDS)


def _enrich_with_context(user_input: str, history: List[Dict]) -> str:
    """For vague follow-ups, prepend the most recent topic from history."""
    clean = _PUNCT_RE.sub('', user_input.lower()).split()
    if len(clean) > 7 or not (set(clean) & _VAGUE_WORDS):
        return user_input
    # Search ALL history messages (user + bot) newest-first for a topic keyword
    for h in reversed(history):
        content = h.get('content', '').lower()
        for keyword, topic in _TOPIC_KEYWORDS.items():
            if keyword in content:
                return f"{topic}: {user_input}"
    return user_input


def _score_match(query_lower: str, candidate: str) -> float:
    """
    Semantic-ish scoring: keyword overlap (no stop words) + char similarity.
    Returns float in [0, 1].
    """
    cand_lower = _PUNCT_RE.sub('', candidate.lower())
    q_clean = _PUNCT_RE.sub('', query_lower)

    if cand_lower == q_clean:
        return 1.0

    q_words = set(q_clean.split()) - _STOP_WORDS
    c_words = set(cand_lower.split()) - _STOP_WORDS

    if q_words and c_words:
        common = q_words & c_words
        overlap = len(common) / max(len(q_words), len(c_words))
    else:
        overlap = 0.0

    char_sim = SequenceMatcher(None, q_clean, cand_lower).ratio()
    # Overlap weighted higher — more robust for mixed Filipino/English
    return max(overlap * 0.85, char_sim * 0.75)


def _detect_intent(text: str) -> str:
    """Returns: complaint | document | tracking | suggestion | greeting | qa"""
    if _match(text, _GREETING_PATS):
        return 'greeting'
    if _match(text, _TRACKING_PATS):
        return 'tracking'
    # Fee/process/how-to questions always go to Q&A — even if document keywords present
    if _match(text, _QUESTION_PATS):
        return 'qa'
    if _match(text, _COMPLAINT_PATS):
        return 'complaint'
    # Strong action phrases: explicitly requesting to get a document
    if _match(text, _DOCUMENT_PATS):
        return 'document'
    # Softer topic match: clearance/certificate mentioned without a question
    if _match(text, _DOCUMENT_TOPIC_PATS):
        return 'document'
    if _match(text, _SUGGESTION_PATS):
        return 'suggestion'
    return 'qa'


# ─── Routed responses ─────────────────────────────────────────────────────────
_ROUTED: Dict[str, Tuple[str, Optional[str]]] = {
    'greeting': (
        "Hello! I'm your Barangay AI Assistant. I can help you with:\n"
        "• Filing complaints or reports\n"
        "• Requesting barangay documents\n"
        "• Tracking your submitted requests\n"
        "• Submitting suggestions\n\n"
        "What would you like to do today?",
        None,
    ),
    'complaint': (
        "I can help you file a complaint. Please go to "
        "Forms & Services → Other Services → Complaint Form to submit your report.\n\n"
        "Fill in the details and the barangay will attend to your concern.",
        "HIGHLIGHT_MENU:complaint",
    ),
    'complaint_drug': (
        "I can help you report illegal drug activity. Go to "
        "Forms & Services → Other Services → Complaint Form and select "
        "Illegal Drug Activity as the category.\n\n"
        "⚠️ If this poses immediate danger, please contact the authorities (PNP) right away.",
        "HIGHLIGHT_MENU:complaint",
    ),
    'document': (
        "You may request a barangay document through the Request section in the app. "
        "Select your needed document, fill in the details, and submit.\n\n"
        "The barangay will process your request and notify you when it's ready. "
        "You may also visit the barangay office personally.",
        "HIGHLIGHT_MENU:document",
    ),
    'tracking': (
        "You can track your submitted request or complaint in the Request Tracking page.\n\n"
        "Do you have a tracking number? If yes, please share it so I can assist you further.",
        "OPEN:tracking",
    ),
    'suggestion': (
        "Thank you for wanting to share your feedback! Please go to the Suggestion Box "
        "to submit your suggestion.\n\n"
        "Your input helps improve barangay services.",
        "HIGHLIGHT_MENU:suggestion",
    ),
}


# ─── Knowledge base (FAQ + dataset) ──────────────────────────────────────────
faq_data = None
_dataset_qa: List[Tuple[str, str]] = []   # (question/instruction, answer)


def load_faq_data():
    global faq_data
    if faq_data is not None:
        return faq_data
    try:
        if os.path.exists(JSON_FILE):
            with open(JSON_FILE, "r", encoding="utf-8") as f:
                faq_data = json.load(f)
            logger.info(f"FAQ loaded: {len(faq_data.get('categories', []))} categories")
    except Exception as e:
        logger.error(f"Error loading FAQ: {e}")
    return faq_data


def _load_dataset():
    """Load bla_dataset.jsonl into _dataset_qa for richer Q&A coverage."""
    global _dataset_qa
    if _dataset_qa:
        return
    dataset_path = os.path.join(
        BASE_DIR, "bla_chatbot_model_gemma_lora_project", "bla_dataset.jsonl"
    )
    if not os.path.exists(dataset_path):
        logger.warning(f"Dataset not found at {dataset_path}")
        return
    try:
        with open(dataset_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                data = json.loads(line)
                instruction = data.get("instruction", "").strip()
                extra = data.get("input", "").strip()
                question = f"{instruction} {extra}".strip() if extra else instruction
                answer = data.get("output", "").strip()
                if question and answer:
                    _dataset_qa.append((question, answer))
        logger.info(f"Dataset loaded: {len(_dataset_qa)} Q&A pairs")
    except Exception as e:
        logger.error(f"Error loading dataset: {e}")


_load_dataset()


def _search_knowledge(query: str, threshold: float = 0.38) -> Optional[str]:
    """
    Search FAQ + dataset for the best answer.
    Uses keyword-overlap scoring (stop-word filtered) + char similarity.
    """
    q_lower = query.lower().strip()
    best_answer, best_score = None, 0.0

    # ── FAQ JSON ──
    data = load_faq_data()
    if data:
        for cat in data.get("categories", []):
            for item in cat.get("questions", []):
                question = item.get("question", "")
                answer = item.get("answer", "")
                if not answer:
                    continue
                if _PUNCT_RE.sub("", question.lower().strip()) == _PUNCT_RE.sub("", q_lower):
                    return answer
                score = _score_match(q_lower, question)
                if score > best_score:
                    best_score, best_answer = score, answer

    # ── JSONL dataset ──
    for instruction, answer in _dataset_qa:
        if _PUNCT_RE.sub("", instruction.lower().strip()) == _PUNCT_RE.sub("", q_lower):
            return answer
        score = _score_match(q_lower, instruction)
        if score > best_score:
            best_score, best_answer = score, answer

    logger.debug(f"Best knowledge score={best_score:.2f} for: {query!r}")
    return best_answer if best_score >= threshold else None


# ─── Gemma generation ─────────────────────────────────────────────────────────
def _generate_with_gemma(user_input: str, history: List[Dict] = None) -> str:
    import torch

    messages = [{"role": "system", "content": _GEMMA_SYSTEM_PROMPT}]

    # Include last 4 history turns for context
    if history:
        for h in history[-4:]:
            role = "user" if h.get("role") == "user" else "assistant"
            messages.append({"role": role, "content": h.get("content", "")})

    messages.append({"role": "user", "content": user_input})

    input_ids = tokenizer.apply_chat_template(
        messages,
        add_generation_prompt=True,
        return_tensors="pt",
    ).to(model.device)

    with torch.no_grad():
        output_ids = model.generate(
            input_ids,
            max_new_tokens=200,
            do_sample=False,
            repetition_penalty=1.1,
            pad_token_id=tokenizer.eos_token_id,
        )

    new_tokens = output_ids[0][input_ids.shape[-1]:]
    return tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


# ─── Public API ───────────────────────────────────────────────────────────────
def generate_chat_response(
    user_input: str,
    history: List[Dict] = None,
) -> Tuple[str, Optional[str]]:
    """
    Returns (message, ui_action).
    ui_action: 'HIGHLIGHT_MENU:complaint' | 'HIGHLIGHT_MENU:document' |
               'HIGHLIGHT_MENU:suggestion' | 'OPEN:tracking' | None
    """
    try:
        intent = _detect_intent(user_input)
        logger.info(f"Intent={intent!r} for: {user_input!r}")

        # Routing intents → instant structured response
        if intent in _ROUTED:
            if intent == 'complaint' and _match(user_input, _DRUG_PATS):
                return _ROUTED['complaint_drug']
            return _ROUTED[intent]

        # Enrich vague follow-ups (e.g. "magkano?" after talking about clearance)
        enriched = _enrich_with_context(user_input, history or [])
        logger.info(f"Enriched query: {enriched!r}")

        # Gemma: use enriched query so the model has full context in the prompt
        if model_loaded:
            gemma_input = enriched if enriched != user_input else user_input
            response = _generate_with_gemma(gemma_input, history)
            if response:
                return response, None

        # Knowledge base: enriched first, then raw
        answer = _search_knowledge(enriched) if enriched != user_input else None
        if not answer:
            answer = _search_knowledge(user_input)
        if answer:
            return answer, None

        # Topic-specific fallback when we know the context but have no exact answer
        if enriched != user_input:
            topic = enriched.split(":")[0].strip()
            return (
                f"Para sa {topic}, ang eksaktong bayad at mga requirements ay maaaring "
                "mag-iba depende sa inyong barangay. Pakibisita ang barangay hall o "
                "makipag-ugnayan sa barangay staff para sa tumpak na impormasyon.",
                None,
            )

        return (
            "I want to make sure I understand correctly. "
            "Are you asking about filing a complaint, requesting a document, "
            "tracking a request, or something else?",
            None,
        )

    except Exception as e:
        logger.error(f"Error in generate_chat_response: {e}", exc_info=True)
        return (
            "I apologize, but I encountered an error. "
            "Please try again or contact the barangay office directly.",
            None,
        )
