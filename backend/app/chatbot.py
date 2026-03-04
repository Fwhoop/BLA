import os
import re
import json
import logging
import requests as _http
from typing import Optional, List, Dict, Tuple
from difflib import SequenceMatcher

try:
    from langdetect import detect, DetectorFactory
    DetectorFactory.seed = 0
    _LANGDETECT_AVAILABLE = True
except ImportError:
    _LANGDETECT_AVAILABLE = False

logger = logging.getLogger(__name__)

# ─── Offline mode: never contact Hugging Face ──────────────────────────────────
# Must be set before any transformers / huggingface_hub imports resolve.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_DATASETS_OFFLINE", "1")

# ─── Tagalog keyword detector ──────────────────────────────────────────────────
_TAGALOG_KEYWORDS = {
    'ang', 'ng', 'sa', 'na', 'ay', 'at', 'ni', 'mga', 'ko', 'mo', 'po',
    'ho', 'ba', 'kaya', 'nga', 'yung', 'rin', 'din', 'naman', 'pala',
    'kasi', 'pero', 'para', 'kung', 'kapag', 'siya', 'sila', 'kami',
    'tayo', 'kayo', 'lang', 'magkano', 'paano', 'bakit', 'kailan', 'saan',
    'sino', 'ano', 'ito', 'iyon', 'dito', 'doon', 'nito', 'nila', 'namin',
    'natin', 'ninyo', 'mayroon', 'wala', 'oo', 'hindi', 'huwag',
    'pumunta', 'kumuha', 'humingi', 'ibigay', 'makuha', 'nandito',
    'gusto', 'pwede', 'puwede', 'kailangan', 'dapat', 'talaga', 'sana',
    'yun', 'daw', 'raw', 'ikaw', 'ako', 'kanila', 'niya',
    'magsumbong', 'magreklamo', 'ireport', 'sumbong', 'reklamo',
    'clearance', 'barangay', 'opisina', 'tanggapan',
}

_PUNCT_STRIP = re.compile(r'[^\w\s]')


def _is_tagalog(text: str) -> bool:
    words = _PUNCT_STRIP.sub('', text.lower()).split()
    if not words:
        return False
    hits = sum(1 for w in words if w in _TAGALOG_KEYWORDS)
    if hits / len(words) > 0.15:
        return True
    if _LANGDETECT_AVAILABLE:
        try:
            return detect(text) == "tl"
        except Exception:
            pass
    return False


# ─── Paths ─────────────────────────────────────────────────────────────────────
BASE_DIR        = os.path.dirname(os.path.abspath(__file__))

# Primary: exact developer path on Windows local machine.
# Fallback: relative path for Railway / Linux container (copy bla_model/ next to chatbot.py).
_EXACT_MODEL_PATH = r"D:\Capstone BLA\BLA\BLA\barangay_legal_aid\backend\app\bla_model"
_REL_MODEL_PATH   = os.path.join(BASE_DIR, "bla_model")
_NEW_MODEL_DIR    = _EXACT_MODEL_PATH if os.path.exists(_EXACT_MODEL_PATH) else _REL_MODEL_PATH

logger.info(f"[STARTUP] bla_model path resolved → {_NEW_MODEL_DIR}")

FULL_MODEL_DIR  = os.path.join(_NEW_MODEL_DIR, "Gemma3_BLA_full")
LORA_ADAPTER_DIR = os.path.join(_NEW_MODEL_DIR, "lora_adapter")
BASE_MODEL_ID   = "google/gemma-3-1b-it"
DATASET_FILE    = os.path.join(_NEW_MODEL_DIR, "bla_dataset (1).jsonl")
JSON_FILE       = os.path.join(os.path.dirname(BASE_DIR), "barangay_law_flutter.json")

# ── MASTER SYSTEM PROMPT ────────────────────────────
MASTER_SYSTEM_PROMPT = """
You are Gemma 3 LoRA – a Philippine Barangay Legal Advisory AI Assistant.

ROLE:
You provide structured legal guidance strictly limited to barangay-level jurisdiction under Philippine law.

SCOPE:
You may answer only about:
- Barangay disputes
- Katarungang Pambarangay process
- Mediation and settlement
- Barangay clearance issues
- Minor civil disputes (utang, boundary, noise, slander, trespass)
- RA 9482 (Anti-Rabies Act)
- RA 9262 (VAWC) – barangay protection level only
- Execution of amicable settlement
- Rights of complainant and respondent in barangay cases

If a topic is outside barangay jurisdiction, respond clearly:
“This matter is outside barangay jurisdiction and requires proper legal or professional consultation.”

RESPONSE STRUCTURE (MANDATORY):

1. Short acknowledgment
2. GENERAL SAFETY ADVICE (only if relevant, generic)
3. LEGAL BASIS (cite correct Philippine law if applicable)
4. RIGHTS OF THE COMPLAINANT
5. STEP-BY-STEP BARANGAY PROCEDURE
6. POSSIBLE OUTCOMES
7. WHAT TO PREPARE
8. Clarifying follow-up questions

RULES:
- Do not fabricate article numbers
- Do not invent legal penalties
- Do not give deep medical advice
- Do not escalate directly to court unless procedure requires it
- Maintain bilingual tone (English + Filipino when natural)
- Maintain consistency across follow-up questions
- Use structured formatting with headings
- Never contradict earlier statements unless correcting clearly
"""

model = None
tokenizer = None
model_loaded = False

# Thread pool for model generation — allows a hard timeout so the server never
# hangs waiting for the model (1 worker: only 1 generation at a time)
import concurrent.futures as _cf
_model_executor = _cf.ThreadPoolExecutor(max_workers=1, thread_name_prefix="gemma_gen")
_GENERATION_TIMEOUT = 45  # seconds — fall back to raw context if exceeded

_LOAD_MODEL    = os.environ.get("LOAD_MODEL", "true").lower() != "false"
_HF_API_TOKEN  = os.environ.get("HF_API_TOKEN", "")
_HF_MODEL_ID   = os.environ.get("HF_MODEL_ID", "fwhoop/bla_model")
_hf_available  = bool(_HF_API_TOKEN)

logger.info(f"[STARTUP] LOAD_MODEL={_LOAD_MODEL} | hf_available={_hf_available} | model_id={_HF_MODEL_ID}")

if _LOAD_MODEL:
    try:
        from transformers import AutoTokenizer, AutoModelForCausalLM
        import torch
        # optional HF helper for downloading model files if local missing
        try:
            from huggingface_hub import snapshot_download
            _HF_HUB_AVAILABLE = True
        except Exception:
            _HF_HUB_AVAILABLE = False

        def _attempt_hf_snapshot_download(target_dir: str) -> bool:
            if not _HF_HUB_AVAILABLE or not _hf_available or not _HF_MODEL_ID:
                return False
            try:
                os.makedirs(target_dir, exist_ok=True)
                logger.info(f"Attempting to download HF model '{_HF_MODEL_ID}' into {target_dir}…")
                snapshot_download(
                    repo_id=_HF_MODEL_ID,
                    token=_HF_API_TOKEN,
                    local_dir=target_dir,
                    allow_patterns=[
                        "config.json",
                        "tokenizer.json",
                        "tokenizer_config.json",
                        "special_tokens_map.json",
                        "*.bin",
                        "*.safetensors",
                        "vocab*",
                    ],
                )
                logger.info("HF model files downloaded (snapshot_download completed).")
                return True
            except Exception as e:
                logger.warning(f"HF snapshot download failed: {e}")
                return False
        def _find_full_model_dir() -> Optional[str]:
            # Check explicit expected path first
            if os.path.exists(FULL_MODEL_DIR) and os.path.exists(os.path.join(FULL_MODEL_DIR, "config.json")):
                return FULL_MODEL_DIR
            # If user placed model files directly under bla_model
            if os.path.exists(_NEW_MODEL_DIR) and os.path.exists(os.path.join(_NEW_MODEL_DIR, "config.json")):
                return _NEW_MODEL_DIR
            # Otherwise look for any subdirectory containing config.json or weights
            if os.path.exists(_NEW_MODEL_DIR):
                for name in os.listdir(_NEW_MODEL_DIR):
                    cand = os.path.join(_NEW_MODEL_DIR, name)
                    if os.path.isdir(cand) and os.path.exists(os.path.join(cand, "config.json")):
                        return cand
            # As a fallback, search the repository upward for any folder named 'bla_model'
            try:
                project_root = os.path.abspath(os.path.join(BASE_DIR, "..", "..", ".."))
                for dirpath, dirnames, filenames in os.walk(project_root):
                    if os.path.basename(dirpath) == 'bla_model':
                        if os.path.exists(os.path.join(dirpath, "config.json")) or any(f.endswith(('.bin', '.safetensors')) for f in filenames):
                            return dirpath
            except Exception:
                pass
            return None

        def _find_lora_adapter_dir() -> Optional[str]:
            # Check explicit expected adapter dir
            if os.path.exists(LORA_ADAPTER_DIR):
                return LORA_ADAPTER_DIR
            # Some users may have placed adapter files directly under bla_model
            if os.path.exists(_NEW_MODEL_DIR):
                # look for typical adapter files or directories
                for name in os.listdir(_NEW_MODEL_DIR):
                    cand = os.path.join(_NEW_MODEL_DIR, name)
                    # simple heuristic: contains adapter_config.json or adapter weights
                    if os.path.isdir(cand) and (
                        os.path.exists(os.path.join(cand, "adapter_config.json"))
                        or any(f.endswith(('.bin', '.safetensors')) for f in os.listdir(cand))
                    ):
                        return cand
            # fallback: search upward for any 'bla_model' directory that looks like an adapter
            try:
                project_root = os.path.abspath(os.path.join(BASE_DIR, "..", "..", ".."))
                for dirpath, dirnames, filenames in os.walk(project_root):
                    if os.path.basename(dirpath) == 'bla_model':
                        for name in os.listdir(dirpath):
                            cand = os.path.join(dirpath, name)
                            if os.path.isdir(cand) and (
                                os.path.exists(os.path.join(cand, "adapter_config.json"))
                                or any(f.endswith(('.safetensors', '.bin')) for f in os.listdir(cand))
                            ):
                                return cand
                        # if adapter files are directly inside this bla_model folder
                        if os.path.exists(os.path.join(dirpath, "adapter_config.json")) or any(f.endswith(('.safetensors', '.bin')) for f in os.listdir(dirpath)):
                            return dirpath
            except Exception:
                pass
            return None

        # ── Strategy 0: no online downloads — model must exist locally ──────────
        # HF_HUB_OFFLINE=1 / TRANSFORMERS_OFFLINE=1 are set at module top.

        # locate a full model directory (accepts files directly under `bla_model`)
        _detected_full_dir = _find_full_model_dir()

        # ── Strategy 1: load the full merged model ────────────────────────────
        if _detected_full_dir and os.path.exists(os.path.join(_detected_full_dir, "config.json")):
            logger.info(f"Loading BLA_Gemma3 full model from {FULL_MODEL_DIR}…")
            try:
                tokenizer = AutoTokenizer.from_pretrained(_detected_full_dir, local_files_only=True)
                model = AutoModelForCausalLM.from_pretrained(
                    _detected_full_dir,
                    device_map="auto",
                    local_files_only=True,
                    # dtype already specified in config.json quantization_config
                    # (bnb_4bit_compute_dtype = float16); don't override here
                )
                model.eval()
                model_loaded = True
                logger.info(f"BLA_Gemma3 full model loaded successfully from {_detected_full_dir}!")
            except Exception as e_full:
                logger.warning(f"Full model load failed ({e_full}). Trying LoRA adapter…")
                tokenizer = None
                model = None

        # ── Strategy 2: LoRA adapter + base model ────────────────────────────
        if not model_loaded:
            _detected_lora_dir = _find_lora_adapter_dir()
        else:
            _detected_lora_dir = None

        if not model_loaded and _detected_lora_dir:
            try:
                from peft import PeftModel
                logger.info(f"Loading LoRA adapter from {_detected_lora_dir}…")
                tokenizer = AutoTokenizer.from_pretrained(_detected_lora_dir, local_files_only=True)
                base = AutoModelForCausalLM.from_pretrained(
                    BASE_MODEL_ID,
                    torch_dtype=torch.float32,
                    device_map="auto",
                    local_files_only=True,
                )
                model = PeftModel.from_pretrained(base, _detected_lora_dir, local_files_only=True)
                model.eval()
                model_loaded = True
                logger.info(f"LoRA adapter loaded successfully from {_detected_lora_dir}!")
            except Exception as e_lora:
                logger.error(f"LoRA adapter load also failed ({e_lora}). Using FAQ fallback.")

    except ImportError as e:
        logger.warning(f"ML libraries not available ({e}). Using FAQ fallback.")
    except Exception as e:
        logger.error(f"Unexpected model load error: {e}. Using FAQ fallback.")
else:
    logger.info("LOAD_MODEL=false — skipping model load (Railway free tier mode).")

# ─── Intent patterns ───────────────────────────────────────────────────────────
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
_DOCUMENT_PATS = [
    r'\bkukuha\b', r'\bkumuha\b', r'\bmag.?request\b',
    r'gusto.{0,15}(kumuha|humingi|mag.?request)',
    r'(humingi|kumuha|request).{0,15}(clearance|certificate|certipikasyon)',
    r'i.{0,10}(want|need).{0,10}(clearance|certificate|document)',
    r'\bpag.?request\b',
]
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
_TRANSLATE_PATS = [
    r'\bin\s+(tagalog|filipino)\b',
    r'\btranslate\b.{0,30}(tagalog|filipino)',
    r'\b(tagalog|filipino)\s+(please|lang|nalang|na lang|version|translation)\b',
    r'\bi-translate\b',
    r'\bsalin\s*(sa)?\s*(tagalog|filipino)\b',
    r'\bpatagalog\b',
    r'\bsagot\s+(sa\s+)?(tagalog|filipino)\b',
    r'^(sa\s+)?(tagalog|filipino)\s*(please|lang|po)?\s*$',
    r'\btagalog\s*(na|lang|please|po)\s*$',
]
_META_PATS = [
    r'\bsimplif(y|ied)\b',
    r'\belaborat(e|ed|e further|e more)\b',
    r'\btell me more\b',
    r'\bmore detail(s)?\b',
    r'\bexplain.{0,15}(concisely|briefly|simpl(y|er|e)|simple words|easier|more|again|further)\b',
    r'\bsummariz(e|ed)\b',
    r'\bi (don\'?t|do not|dont) (fully )?understand\b',
    r'\bcan you (clarify|rephrase|explain (again|more|further|better|clearly))\b',
    r'\bwhat do you mean\b',
    r'\bin simple (words|terms|language)\b',
    r'\bmake it (simpler|clearer|shorter|easier)\b',
    r'\b(give|provide) more (info|information|detail(s)?|context|explanation)\b',
    r'\brepeat (that|your answer|the answer)\b',
    r'\bsay that again\b',
]
_CORRECTION_PATS = [
    r"(i )?(didn'?t|did not|dont|hindi) ask (about|that|for that)",
    r"that'?s not what i (asked|meant|said|was asking)",
    r"wrong (answer|response|info|information)",
    r"not what i (asked|meant|said|was asking)(?: about)?",
    r"please (answer|address) my (question|concern)",
    r"you (didn'?t|did not|didn't) answer my (question|concern)",
    r"i (was asking|meant|mean) about",
    r"hindi (iyon|yan|yon|yun) ang (tanong|ibig sabihin|tinanong) ko",
]
_GREETING_PATS = [
    r'^(hi|hello|hey|good\s+morning|good\s+afternoon|good\s+evening|'
    r'kumusta|kamusta|musta|hola|yo|sup|greetings?|ola|test|testing|'
    r'magandang\s+\w+)[\s!.?]*$',
]
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
_VAGUE_WORDS = {
    'magkano', 'how much', 'paano', 'how to', 'kailan', 'when',
    'gaano', 'ito', 'iyon', 'that', 'saan', 'where', 'bakit', 'why',
    'ano', 'what', 'sino', 'who', 'dito', 'doon', 'nito', 'nun',
    # follow-up / requirements context triggers
    'requirements', 'requirement', 'kailangan', 'kailangan', 'dapat',
    'yun', 'yon', 'nyan', 'iyan', 'steps', 'process', 'procedure',
    'how', 'explain', 'tell', 'paano', 'anong', 'ilang', 'magkano',
}
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
    # extended topic context for follow-up questions
    '4ps': '4Ps (Pantawid Pamilyang Pilipino Program)',
    'pantawid': '4Ps (Pantawid Pamilyang Pilipino Program)',
    'pamilyang pilipino': '4Ps (Pantawid Pamilyang Pilipino Program)',
    'dswd': '4Ps (Pantawid Pamilyang Pilipino Program / DSWD)',
    'vawc': 'Violence Against Women and Children (VAWC, RA 9262)',
    'domestic violence': 'Violence Against Women and Children (VAWC)',
    'bullying': 'Anti-Bullying Act (RA 10627)',
    'cyberbullying': 'Anti-Bullying Act / Cybercrime Prevention Act',
    'cybercrime': 'Cybercrime Prevention Act (RA 10175)',
    'pwd': 'Magna Carta for Persons with Disability (PWD)',
    'disability': 'Magna Carta for Persons with Disability (PWD)',
    'senior': 'Expanded Senior Citizens Act (RA 9994)',
    'elderly': 'Expanded Senior Citizens Act (RA 9994)',
    'solo parent': "Solo Parents' Welfare Act (RA 8972)",
    'drug': 'Comprehensive Dangerous Drugs Act (RA 9165)',
    'drugs': 'Comprehensive Dangerous Drugs Act (RA 9165)',
    'droga': 'Comprehensive Dangerous Drugs Act (RA 9165)',
    'blotter': 'barangay blotter / incident report',
    'protection order': 'Barangay Protection Order (BPO)',
    'bpo': 'Barangay Protection Order (BPO)',
    'tanod': 'barangay tanod duties and authority',
    'kapitan': 'Punong Barangay / Barangay Captain duties',
    'punong barangay': 'Punong Barangay duties under RA 7160',
    'sk': 'Sangguniang Kabataan (SK)',
    'sangguniang kabataan': 'Sangguniang Kabataan (SK)',
    'fire': 'fire emergency procedure (call BFP at 117)',
    'emergency': 'emergency contacts and barangay response',
    'dog bite': 'animal bite response and anti-rabies protocol',
    'kagat': 'animal bite response and anti-rabies protocol',
    'theft': 'reporting theft to barangay / PNP',
    'robbery': 'reporting theft or robbery',
    'nanakaw': 'reporting theft to barangay / PNP',
    'noise': 'barangay noise ordinance',
    'curfew': 'barangay curfew ordinance for minors',
    'ordinance': 'barangay ordinance',
    'ordinansa': 'barangay ordinance',
    'magna carta': 'Magna Carta for various sectors',
}

_PUNCT_RE = re.compile(r'[^\w\s]')
_STOP_WORDS = {
    'ang', 'ng', 'sa', 'na', 'ay', 'at', 'ni', 'mga', 'ko', 'mo', 'niya',
    'namin', 'natin', 'ninyo', 'nila', 'ba', 'po', 'ho', 'kaya', 'nga',
    'yung', 'ung', 'siya', 'sila', 'kami', 'tayo', 'kayo', 'lang', 'din',
    'rin', 'naman', 'pala', 'kasi', 'pero', 'para', 'kung', 'kapag',
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
    words = _PUNCT_RE.sub('', text.lower()).split()
    return len(words) <= 7 and bool(set(words) & _VAGUE_WORDS)


def _enrich_with_context(user_input: str, history: List[Dict]) -> str:
    clean = _PUNCT_RE.sub('', user_input.lower()).split()
    if len(clean) > 7 or not (set(clean) & _VAGUE_WORDS):
        return user_input
    for h in reversed(history):
        content = h.get('content', '').lower()
        for keyword, topic in _TOPIC_KEYWORDS.items():
            if keyword in content:
                return f"{topic}: {user_input}"
    return user_input


def _score_match(query_lower: str, candidate: str) -> float:
    cand_lower = _PUNCT_RE.sub('', candidate.lower())
    q_clean = _PUNCT_RE.sub('', query_lower)
    if cand_lower == q_clean:
        return 1.0
    q_words_all = q_clean.split()
    c_words_all = cand_lower.split()
    q_words = set(q_words_all) - _STOP_WORDS
    c_words = set(c_words_all) - _STOP_WORDS
    overlap = (
        len(q_words & c_words) / max(len(q_words), len(c_words))
        if q_words and c_words else 0.0
    )
    # Bigram overlap — rewards adjacent word pairs (more contextual than unigrams)
    q_bigrams = set(zip(q_words_all, q_words_all[1:]))
    c_bigrams = set(zip(c_words_all, c_words_all[1:]))
    bigram_sim = (
        len(q_bigrams & c_bigrams) / max(len(q_bigrams), len(c_bigrams))
        if q_bigrams and c_bigrams else 0.0
    )
    char_sim = SequenceMatcher(None, q_clean, cand_lower).ratio()
    return max(overlap * 0.85, bigram_sim * 0.90, char_sim * 0.70)


def _detect_intent(text: str) -> str:
    if _match(text, _GREETING_PATS):
        return 'greeting'
    if _match(text, _TRANSLATE_PATS):
        return 'translate'
    if _match(text, _CORRECTION_PATS):
        return 'correction'
    if _match(text, _META_PATS):
        return 'meta'
    if _match(text, _TRACKING_PATS):
        return 'tracking'
    if _match(text, _QUESTION_PATS):
        return 'qa'
    if _match(text, _COMPLAINT_PATS):
        return 'complaint'
    if _match(text, _DOCUMENT_PATS):
        return 'document'
    if _match(text, _DOCUMENT_TOPIC_PATS):
        return 'document'
    if _match(text, _SUGGESTION_PATS):
        return 'suggestion'
    return 'qa'


# ─── Routed responses (more detailed) ─────────────────────────────────────────
_ROUTED: Dict[str, Tuple[str, Optional[str]]] = {
    'greeting': (
        "Magandang araw! I'm your Barangay Legal Aid (BLA) AI Assistant. "
        "I'm here to provide detailed guidance on barangay services and your legal rights as a resident.\n\n"
        "I can help you with:\n"
        "• **Filing complaints** — step-by-step process, your rights, and what to expect\n"
        "• **Barangay documents** — clearances, certificates, requirements, and fees\n"
        "• **Legal information** — Katarungang Pambarangay, RA 7160, and your rights\n"
        "• **Tracking requests** — status of your submitted documents or complaints\n"
        "• **Suggestions** — share feedback to improve barangay services\n\n"
        "What do you need help with today? Feel free to ask in Filipino or English.",
        None,
    ),
    'complaint': (
        "I can help you file a formal complaint with the barangay.\n\n"
        "**How to file a complaint:**\n"
        "1. Go to **Forms & Services → Other Services → Complaint Form** in this app\n"
        "2. Select the complaint category (noise, drugs, harassment, property dispute, etc.)\n"
        "3. Provide a detailed description of the incident including date, time, and location\n"
        "4. Submit your complaint — it will be received by the barangay office\n\n"
        "**What happens next:**\n"
        "• The barangay will review your complaint and may summon both parties\n"
        "• Under the Katarungang Pambarangay (RA 7160), the Lupong Tagapamayapa will "
        "attempt mediation and conciliation first\n"
        "• If unresolved within 30 days, a Certificate to File Action is issued\n\n"
        "Do you want more details about a specific type of complaint?",
        "HIGHLIGHT_MENU:complaint",
    ),
    'complaint_drug': (
        "You can report illegal drug activity through the barangay.\n\n"
        "**Steps to report:**\n"
        "1. Go to **Forms & Services → Complaint Form** and select **Illegal Drugs** as category\n"
        "2. Describe the incident with as much detail as possible (but do NOT endanger yourself)\n"
        "3. Submit — the barangay will coordinate with the PDEA and PNP\n\n"
        "⚠️ **If there is immediate danger**, contact the PNP at **911** or your local police station first.\n\n"
        "Under RA 9165 (Comprehensive Dangerous Drugs Act), reporting drug activity is protected "
        "and your identity can be kept confidential upon request.",
        "HIGHLIGHT_MENU:complaint",
    ),
    'document': (
        "You can request barangay documents through this app.\n\n"
        "**Available Documents & Typical Requirements:**\n"
        "• **Barangay Clearance** — valid ID, proof of residency, ₱50–₱100 fee\n"
        "• **Certificate of Residency** — valid ID showing barangay address\n"
        "• **Certificate of Indigency** — proof of income or affidavit of poverty\n"
        "• **Certificate of Good Moral Character** — valid ID, sometimes with endorsement\n\n"
        "**How to request:**\n"
        "1. Go to the **Request** section in the app\n"
        "2. Select your needed document\n"
        "3. Fill in the details and submit\n"
        "4. The barangay will process and notify you when ready (usually 1–3 days)\n\n"
        "You may also visit the barangay hall in person. Bring a valid government-issued ID.\n\n"
        "Which specific document do you need? I can give you the exact requirements.",
        "HIGHLIGHT_MENU:document",
    ),
    'tracking': (
        "You can track your requests and complaints in the app.\n\n"
        "**For document requests:** Check the Request section for status updates "
        "(Pending → Processing → Ready for Pickup).\n\n"
        "**For complaints:** The barangay will contact you for mediation schedules. "
        "Under RA 7160, mediation must begin within 3 days of filing, and the entire "
        "conciliation process should conclude within 30 days.\n\n"
        "If you have a specific concern about a pending request, please share more details "
        "and I'll do my best to help.",
        "OPEN:tracking",
    ),
    'suggestion': (
        "Thank you for wanting to share your feedback — it helps improve barangay services!\n\n"
        "Please go to **Forms & Services → Suggestion Box** to submit your suggestion. "
        "You may submit anonymously if you prefer.\n\n"
        "Your suggestion will be reviewed by the barangay administration.",
        "HIGHLIGHT_MENU:suggestion",
    ),
}

# ─── Tagalog versions of routed responses ──────────────────────────────────────
_ROUTED_TL: Dict[str, Tuple[str, Optional[str]]] = {
    'greeting': (
        "Magandang araw! Ako ang inyong AI Legal Assistant ng Barangay Legal Aid (BLA). "
        "Handa akong tumulong sa inyo tungkol sa mga serbisyo ng barangay at sa inyong mga karapatan.\n\n"
        "Maaari akong tumulong sa:\n"
        "• **Pag-file ng reklamo** — hakbang-hakbang na proseso at inyong mga karapatan\n"
        "• **Mga dokumento ng barangay** — clearance, sertipiko, at mga kinakailangan\n"
        "• **Legal na impormasyon** — Katarungang Pambarangay, RA 7160, at inyong mga karapatan\n"
        "• **Pagsubaybay ng kahilingan** — status ng inyong mga isinumiteng dokumento\n"
        "• **Mga mungkahi** — ibahagi ang inyong feedback para mapabuti ang serbisyo\n\n"
        "Ano ang maipaglilingkod ko sa inyo ngayon?",
        None,
    ),
    'complaint': (
        "Maaari kong tulungan kayong mag-file ng pormal na reklamo sa barangay.\n\n"
        "**Paano mag-file ng reklamo:**\n"
        "1. Pumunta sa **Forms & Services → Other Services → Complaint Form** sa app na ito\n"
        "2. Piliin ang kategorya ng reklamo (ingay, droga, panggagambala, alitan sa ari-arian, atbp.)\n"
        "3. Ilarawan nang detalyado ang insidente kasama ang petsa, oras, at lugar\n"
        "4. I-submit ang inyong reklamo — matatanggap ito ng tanggapan ng barangay\n\n"
        "**Ano ang mangyayari pagkatapos:**\n"
        "• Susuriin ng barangay ang reklamo at maaaring ipatawag ang magkabilang panig\n"
        "• Sa ilalim ng Katarungang Pambarangay (RA 7160), ang Lupong Tagapamayapa ay "
        "magsasagawa ng mediasyon at konsiliasyon muna\n"
        "• Kung hindi mapayapa sa loob ng 30 araw, maglalabas ng Certificate to File Action\n\n"
        "Gusto ba ninyong malaman ang higit pa tungkol sa isang partikular na uri ng reklamo?",
        "HIGHLIGHT_MENU:complaint",
    ),
    'complaint_drug': (
        "Maaari ninyong iulat ang illegal na aktibidad sa droga sa barangay.\n\n"
        "**Mga hakbang para mag-ulat:**\n"
        "1. Pumunta sa **Forms & Services → Complaint Form** at piliin ang **Illegal Drugs** bilang kategorya\n"
        "2. Ilarawan ang insidente nang may detalye hangga't maaari (huwag ilagay ang sarili sa panganib)\n"
        "3. I-submit — makikipagtulungan ang barangay sa PDEA at PNP\n\n"
        "⚠️ **Kung may agarang panganib**, makipag-ugnayan sa PNP sa **911** o sa pinakamalapit na istasyon ng pulis.\n\n"
        "Sa ilalim ng RA 9165 (Comprehensive Dangerous Drugs Act), ang pag-uulat ng aktibidad sa droga "
        "ay protektado at ang inyong pagkakakilanlan ay maaaring panatilihing lihim.",
        "HIGHLIGHT_MENU:complaint",
    ),
    'document': (
        "Maaari kayong humiling ng mga dokumento ng barangay sa pamamagitan ng app na ito.\n\n"
        "**Mga Available na Dokumento at Karaniwang Kinakailangan:**\n"
        "• **Barangay Clearance** — valid ID, patunay ng paninirahan, ₱50–₱100 bayad\n"
        "• **Certificate of Residency** — valid ID na nagpapakita ng address sa barangay\n"
        "• **Certificate of Indigency** — patunay ng kita o affidavit of poverty\n"
        "• **Certificate of Good Moral Character** — valid ID, minsan may endorsement\n\n"
        "**Paano humiling:**\n"
        "1. Pumunta sa seksyon ng **Request** sa app\n"
        "2. Piliin ang dokumentong kailangan ninyo\n"
        "3. Punan ang mga detalye at i-submit\n"
        "4. Ipoproseso ng barangay at aabisuhan kayo kung kailan ito handa (kadalasan 1–3 araw)\n\n"
        "Maaari rin kayong pumunta nang personal sa barangay hall. Magdala ng valid ID.\n\n"
        "Aling dokumento ang kailangan ninyo? Ibibigay ko ang eksaktong kinakailangan.",
        "HIGHLIGHT_MENU:document",
    ),
    'suggestion': (
        "Salamat sa pagbabahagi ng inyong feedback — nakakatulong ito sa pagpapabuti ng serbisyo!\n\n"
        "Pumunta sa **Forms & Services → Suggestion Box** para isumite ang inyong mungkahi. "
        "Maaari kayong magsumite nang hindi nagpapakilala kung gusto ninyo.\n\n"
        "Susuriin ng administrasyon ng barangay ang inyong mungkahi.",
        "HIGHLIGHT_MENU:suggestion",
    ),
}


# ─── Knowledge base ────────────────────────────────────────────────────────────
faq_data = None
_dataset_qa: List[Tuple[str, str]] = []


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
    global _dataset_qa
    if _dataset_qa:
        return

    # Try new dataset first, fall back to old one
    paths = [
        DATASET_FILE,
        os.path.join(BASE_DIR, "bla_chatbot_model_gemma_lora_project", "bla_dataset.jsonl"),
    ]
    for path in paths:
        if not os.path.exists(path):
            continue
        try:
            count = 0
            with open(path, "r", encoding="utf-8") as f:
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
                        count += 1
            logger.info(f"Dataset loaded: {count} Q&A pairs from {path}")
            return
        except Exception as e:
            logger.error(f"Error loading dataset from {path}: {e}")


_load_dataset()


def _search_knowledge(query: str, threshold: float = 0.52) -> Optional[str]:
    q_lower = query.lower().strip()
    best_answer, best_score = None, 0.0
    faq_best, faq_score = None, 0.0

    # ── FAQ JSON ──
    data = load_faq_data()
    if data:
        for cat in data.get("categories", []):
            cat_name = re.sub(r'^user asks about\s+', '', cat.get("name", ""), flags=re.I)
            for item in cat.get("questions", []):
                question = item.get("question", "")
                answer = item.get("answer", "")
                if not answer:
                    continue
                if _PUNCT_RE.sub("", question.lower().strip()) == _PUNCT_RE.sub("", q_lower):
                    return answer
                q_score = _score_match(q_lower, question)
                cat_score = _score_match(q_lower, cat_name) * 0.65
                score = max(q_score, cat_score)
                if score > faq_score:
                    faq_score, faq_best = score, answer

    # ── JSONL dataset ──
    ds_best, ds_score = None, 0.0
    for instruction, answer in _dataset_qa:
        if _PUNCT_RE.sub("", instruction.lower().strip()) == _PUNCT_RE.sub("", q_lower):
            return answer
        score = _score_match(q_lower, instruction)
        if score > ds_score:
            ds_score, ds_best = score, answer

    # FAQ wins at a lower threshold (curated, higher quality)
    if faq_score >= threshold - 0.07 and faq_score >= ds_score - 0.10:
        best_score, best_answer = faq_score, faq_best
    elif ds_score > faq_score + 0.10:
        best_score, best_answer = ds_score, ds_best
    elif faq_best:
        best_score, best_answer = faq_score, faq_best
    else:
        best_score, best_answer = ds_score, ds_best

    logger.debug(f"Knowledge search: score={best_score:.2f}, faq={faq_score:.2f}, ds={ds_score:.2f}")
    return best_answer if best_score >= threshold else None


# ─── Typo / shorthand normalizer ───────────────────────────────────────────────
# Word-level substitution for common Filipino & English shorthand / typos
_TYPO_MAP: Dict[str, str] = {
    # ── Tagalog question words ──────────────────────────────────────────────────
    'bkit': 'bakit',   'bakt': 'bakit',    'bkt': 'bakit',
    'mgkano': 'magkano', 'mkagno': 'magkano', 'mgkno': 'magkano', 'mkno': 'magkano',
    'pano': 'paano',   'pno': 'paano',     'panu': 'paano',
    'klan': 'kailan',  'kln': 'kailan',    'klan': 'kailan',
    'sn': 'saan',      'san': 'saan',
    'anu': 'ano',      'ano2': 'ano ano',   'ano3': 'ano ano ano',
    # ── Tagalog common words ────────────────────────────────────────────────────
    'dn': 'din',       'rn': 'rin',
    'nman': 'naman',   'nmn': 'naman',
    'kya': 'kaya',     'kia': 'kaya',
    'tlga': 'talaga',  'tlg': 'talaga',
    'pde': 'pwede',    'pwde': 'pwede',    'pude': 'pwede',
    'sge': 'sige',     'sgi': 'sige',
    'pki': 'pakiusap', 'pakiusap': 'pakiusap',
    'wla': 'wala',     'wala': 'wala',
    'kpg': 'kapag',    'kng': 'kung',
    'dto': 'dito',     'dn': 'doon',
    'nto': 'nito',     'nyon': 'niyon',
    'mkikita': 'makikita', 'mkita': 'makita',
    'mron': 'mayroon', 'mroon': 'mayroon', 'meron': 'mayroon',
    # ── English shorthand ───────────────────────────────────────────────────────
    'wat': 'what',     'wut': 'what',      'wht': 'what',
    'hw': 'how',       'haw': 'how',
    'wer': 'where',    'whr': 'where',
    'wen': 'when',     'whn': 'when',
    'tagalo': 'tagalog', 'tagolog': 'tagalog',   # common typos
    'pls': 'please',   'plz': 'please',    'plez': 'please',
    'ur': 'your',      'urs': 'yours',
    'dat': 'that',     'dis': 'this',
    'dey': 'they',     'dem': 'them',      'der': 'there',
    'cant': 'cannot',  'wont': 'will not', 'dont': "do not",
    'doesnt': 'does not', 'isnt': 'is not', 'wasnt': 'was not',
    'coz': 'because',  'cuz': 'because',
    'gonna': 'going to', 'wanna': 'want to',
    'u': 'you',        'r': 'are',         'yr': 'your',
    'thx': 'thanks',   'ty': 'thank you',
    'ppl': 'people',   'govt': 'government', 'brgy': 'barangay',
    'doc': 'document', 'docs': 'documents',
    'req': 'request',  'reqs': 'requirements',
    'cert': 'certificate', 'certs': 'certificates',
    'dept': 'department', 'dpt': 'department',
    'info': 'information', 'infos': 'information',
}

_WORD_RE = re.compile(r'\b\w+\b')


def _normalize_typos(text: str) -> str:
    """Replace known shorthand/typo words while preserving surrounding punctuation."""
    def _replace(m: re.Match) -> str:
        word = m.group()
        return _TYPO_MAP.get(word.lower(), word)
    return _WORD_RE.sub(_replace, text)


# ─── Query expansion ───────────────────────────────────────────────────────────
# Maps common abbreviations/short names → full legal description for prompt injection
_LEGAL_ABBREVIATIONS: Dict[str, str] = {
    'vawc':                          'Violence Against Women and their Children Act (Republic Act 9262, VAWC)',
    'ra 9262':                       'Republic Act 9262 (VAWC — Violence Against Women and their Children)',
    'ra 7610':                       'Republic Act 7610 (Special Protection of Children Against Abuse, Exploitation and Discrimination)',
    'ra 11313':                      'Republic Act 11313 (Safe Spaces Act / Bawal Bastos Law)',
    'ra 10627':                      'Republic Act 10627 (Anti-Bullying Act of 2013)',
    'anti-bullying':                 'Anti-Bullying Act (Republic Act 10627)',
    'bullying act':                  'Anti-Bullying Act of 2013 (Republic Act 10627)',
    'bullying':                      'Anti-Bullying Act (Republic Act 10627)',
    'magna carta':                   'Magna Carta for Persons with Disability (Republic Act 7277 as amended by RA 9442 and RA 10524)',
    'magna carta for persons with disability': 'Magna Carta for Persons with Disability (Republic Act 7277)',
    'magna carta for pwd':           'Magna Carta for Persons with Disability (Republic Act 7277)',
    'pwd':                           'rights of Persons with Disability under the Magna Carta (Republic Act 7277)',
    'persons with disabilities':     'Magna Carta for Persons with Disability (Republic Act 7277)',
    'solo parent':                   'Solo Parents\' Welfare Act (Republic Act 8972)',
    'ra 8972':                       'Republic Act 8972 (Solo Parents\' Welfare Act)',
    'senior citizen':                'Expanded Senior Citizens Act (Republic Act 9994)',
    'ra 9994':                       'Republic Act 9994 (Expanded Senior Citizens Act of 2010)',
    'katarungang pambarangay':       'Katarungang Pambarangay (Barangay Justice System under RA 7160, Chapter 7)',
    'lupon':                         'Lupong Tagapamayapa (Barangay Peace Committee under RA 7160)',
    'lupong tagapamayapa':           'Lupong Tagapamayapa (Barangay Peace Committee under RA 7160)',
    'rpc':                           'Revised Penal Code of the Philippines (Act No. 3815)',
    'revised penal code':            'Revised Penal Code of the Philippines (Act No. 3815)',
    'civil code':                    'Civil Code of the Philippines (Republic Act 386)',
    'family code':                   'Family Code of the Philippines (Executive Order 209)',
    'ra 7160':                       'Republic Act 7160 (Local Government Code of 1991)',
    'local government code':         'Republic Act 7160 (Local Government Code of 1991)',
    'anti-hazing':                   'Anti-Hazing Act of 2018 (Republic Act 11053)',
    'ra 11053':                      'Republic Act 11053 (Anti-Hazing Act of 2018)',
    'cybercrime':                    'Cybercrime Prevention Act (Republic Act 10175)',
    'ra 10175':                      'Republic Act 10175 (Cybercrime Prevention Act of 2012)',
    'data privacy':                  'Data Privacy Act (Republic Act 10173)',
    'ra 9165':                       'Republic Act 9165 (Comprehensive Dangerous Drugs Act of 2002)',
    'dangerous drugs':               'Comprehensive Dangerous Drugs Act (Republic Act 9165)',
}

_QUESTION_WORDS = {
    'what', 'how', 'when', 'where', 'why', 'who', 'which', 'explain', 'describe',
    'paano', 'ano', 'sino', 'bakit', 'kailan', 'saan', 'magkano', 'gaano',
    'ibigay', 'ipaliwanag', 'sabihin', 'tell', 'define', 'list', 'enumerate',
}

# Words that indicate a meta/language request — must NOT be expanded as legal topics
_EXPANSION_BLOCKLIST = {
    'translate', 'translation', 'tagalog', 'filipino', 'pilipino',
    'english', 'ingles', 'salin', 'patagalog', 'i-translate',
    'repeat', 'again', 'more', 'details', 'elaborate', 'rephrase',
    'sorry', 'thanks', 'thank', 'okay', 'yes', 'no', 'please',
}


def _expand_query(text: str) -> str:
    """
    Expand short topic-only queries so the model gives a full, structured answer.

    E.g. "VAWC" → "Please explain the Violence Against Women... in detail..."
    """
    text_lower = text.lower().strip()

    # Check abbreviations (longest match first to avoid partial matches)
    for abbr in sorted(_LEGAL_ABBREVIATIONS, key=len, reverse=True):
        if abbr in text_lower:
            full = _LEGAL_ABBREVIATIONS[abbr]
            return (
                f"Explain the {full} in detail: what it protects, key provisions and penalties, "
                f"and the step-by-step process for a barangay resident to file a complaint or seek help."
            )

    # Short topic query with no question word or question mark
    words = text.strip().split()
    has_question = (
        any(w.lower() in _QUESTION_WORDS for w in words)
        or text.strip().endswith('?')
    )
    # Don't expand meta/language-related phrases (translate, tagalog, etc.)
    if any(w.lower() in _EXPANSION_BLOCKLIST for w in words):
        return text
    if len(words) <= 6 and not has_question:
        return (
            f"Explain '{text.strip()}' in detail: its legal basis under Philippine law, "
            f"key provisions, rights and penalties, and how a barangay resident can seek help or file a complaint."
        )

    return text


# ─── Pre-written instant answers for known legal topics ────────────────────────
# These are returned immediately without calling the model, avoiding timeouts.
# Keys are lowercase abbreviations / keywords that a user would type.
_LEGAL_TOPIC_ANSWERS: Dict[str, str] = {
    'vawc': (
        "**Violence Against Women and Their Children Act (Republic Act 9262)**\n\n"
        "RA 9262 protects women and their children from physical, sexual, psychological, "
        "and economic abuse by a spouse, former spouse, or intimate partner.\n\n"
        "**Who is protected:**\n"
        "• Wives or former wives\n"
        "• Women in intimate or dating relationships\n"
        "• Women with a common child with the abuser\n\n"
        "**Covered abuse:** physical violence, sexual assault, psychological abuse "
        "(threats, stalking, harassment), and economic control (withholding money, "
        "destroying property).\n\n"
        "**Penalties:** 6 months to 12 years imprisonment depending on severity.\n\n"
        "**How to seek help at the barangay:**\n"
        "1. Go to the **Barangay VAW Desk** — every barangay is required to have one\n"
        "2. Request a **Barangay Protection Order (BPO)** — must be issued within 24 hours\n"
        "   to stop the abuser from contacting or approaching you\n"
        "3. For serious cases, file at the **Police Station** or **Regional Trial Court**\n"
        "4. Call **DSWD Hotline 1343** or **911** for emergency shelter and assistance\n\n"
        "You do NOT need the abuser present to get a Protection Order. "
        "The barangay must act immediately upon your report."
    ),
    'bullying': (
        "**Anti-Bullying Act of 2013 (Republic Act 10627)**\n\n"
        "RA 10627 requires all elementary and secondary schools to adopt anti-bullying "
        "policies to protect every student from harm.\n\n"
        "**Forms of bullying covered:**\n"
        "• Physical: hitting, kicking, pushing\n"
        "• Verbal: name-calling, threats, taunting\n"
        "• Cyberbullying: online harassment, spreading rumors via social media\n"
        "• Social: deliberately excluding a student, public humiliation\n\n"
        "**What schools must do:**\n"
        "1. Maintain a written Anti-Bullying Policy posted in school\n"
        "2. Investigate all reports within **3 days**\n"
        "3. Resolve the case and impose appropriate sanctions within **10 days**\n"
        "4. Record every incident in a Bullying Incident Report Book\n"
        "5. Notify parents of both the bully and the bullied student\n\n"
        "**Steps to report bullying:**\n"
        "1. Report to the **Class Adviser** or **School Principal** with full details\n"
        "2. If the school fails to act, escalate to the **School Division Superintendent (DepEd)**\n"
        "3. For cyberbullying involving threats, also report to **PNP Anti-Cybercrime Group**\n"
        "4. If the bully is a minor in your community, you may file a barangay complaint "
        "for mediation under the Katarungang Pambarangay"
    ),
    'magna carta': (
        "**Magna Carta for Persons with Disability (Republic Act 7277, as amended)**\n\n"
        "RA 7277 (amended by RA 9442 and RA 10524) grants rights and privileges to "
        "Filipinos with physical, visual, hearing, intellectual, or psychosocial disabilities.\n\n"
        "**Key benefits:**\n"
        "• **20% discount** on medicines, medical/dental services, hotels, restaurants, "
        "recreational centers, and domestic transportation\n"
        "• **5% discount** on basic necessities and prime commodities\n"
        "• Discounts are **VAT-exempt**\n"
        "• Priority lanes in government offices, hospitals, and commercial establishments\n"
        "• Free public education; scholarship programs for PWDs\n"
        "• Under RA 10524, government agencies must reserve at least **1% of positions** for PWDs\n\n"
        "**How to get a PWD ID (free of charge):**\n"
        "1. Go to your **Barangay Hall** or **City/Municipal Social Welfare Office (CSWDO)**\n"
        "2. Bring: medical certificate or diagnosis, valid ID, 2 passport-size photos, "
        "and your birth certificate\n"
        "3. Fill out the PWD Registration Form\n"
        "4. ID is issued within 3–7 working days\n\n"
        "The PWD ID is renewable annually and valid nationwide."
    ),
    'solo parent': (
        "**Solo Parents' Welfare Act (Republic Act 8972)**\n\n"
        "RA 8972 provides benefits and support to solo parents raising their children alone.\n\n"
        "**Who qualifies as a solo parent:**\n"
        "• Parent whose spouse has died, is detained, or has abandoned the family for ≥1 year\n"
        "• Woman who gave birth without marriage and is raising the child alone\n"
        "• Parent whose spouse is physically or mentally incapacitated\n"
        "• Relative caring for a child whose parents are deceased or incapacitated\n\n"
        "**Benefits:**\n"
        "• **Flexible work schedule** — employers must grant at least 1 hour flexible work/day\n"
        "• **7 working days paid parental leave** per year (on top of other leaves)\n"
        "• Educational assistance and scholarship programs for solo parents and their children\n"
        "• Priority in government housing programs (Pag-IBIG, NHA)\n"
        "• Medical assistance from DSWD and local government units\n\n"
        "**How to get a Solo Parent ID:**\n"
        "1. Go to the **City/Municipal Social Welfare and Development Office (CSWDO)**\n"
        "2. Bring: child's birth certificate, proof of solo parent status "
        "(death certificate, court order, or **barangay certification**), valid ID, passport photo\n"
        "3. Register and fill out the Solo Parent Registration Form\n"
        "4. ID is free and valid for 1 year (renewable annually)\n\n"
        "The **barangay can issue the solo parent status certification** needed for registration."
    ),
    'senior citizen': (
        "**Expanded Senior Citizens Act (Republic Act 9994)**\n\n"
        "RA 9994 grants benefits and privileges to all Filipino citizens aged **60 years and above**.\n\n"
        "**Key benefits:**\n"
        "• **20% discount + VAT exemption** on: medicines, medical/dental services, "
        "hotels, restaurants, domestic air/sea/land transportation, and recreational centers\n"
        "• **Free medical and dental services** in all government hospitals and clinics\n"
        "• **Free flu and pneumococcal vaccines** from government health centers\n"
        "• **Priority lanes** in ALL establishments, offices, and hospitals\n"
        "• **₱500/month social pension** for indigent senior citizens (through DSWD)\n"
        "• **10% discount on electricity, water, and telephone utilities** "
        "(if account is under the senior citizen's name)\n\n"
        "**How to get an OSCA ID (free of charge):**\n"
        "1. Go to the **Office for Senior Citizens Affairs (OSCA)** at the City/Municipal Hall\n"
        "2. Bring: birth certificate or baptismal record, valid ID, barangay clearance, "
        "2 passport-size photos\n"
        "3. Fill out the registration form\n"
        "4. ID is issued within 1–3 working days\n\n"
        "The **barangay assists senior citizens** in claiming benefits and may issue "
        "a Senior Citizen Residence Certificate."
    ),
    'katarungang pambarangay': (
        "**Katarungang Pambarangay — Barangay Justice System (RA 7160, Chapter 7)**\n\n"
        "The Katarungang Pambarangay (KP) is the barangay-level dispute resolution system "
        "that settles community conflicts through mediation — without going to court.\n\n"
        "**Disputes covered:**\n"
        "• Neighbor conflicts (noise, boundaries, damage)\n"
        "• Minor physical injuries and oral defamation\n"
        "• Small debt collection\n"
        "• Property damage and simple contract disputes\n"
        "• Most civil and criminal cases where both parties are in the same barangay\n\n"
        "**Step-by-step process:**\n"
        "1. **File the complaint** at the Barangay Hall — the Lupon Secretary records it\n"
        "2. **Punong Barangay mediates** — both parties are called within **3 days**\n"
        "3. If mediation fails, a **Pangkat ng Tagapagkasundo** (3-member conciliation panel) "
        "is formed\n"
        "4. The Pangkat has **30 days** (extendable by 15 days) to reach a settlement\n"
        "5. If successful → **Amicable Settlement** signed (has force of a court judgment)\n"
        "6. If settlement fails → **Certificate to File Action** issued, "
        "allowing you to bring the case to court\n\n"
        "**Important:** For most disputes between residents of the same barangay, you "
        "**must go through KP first** before filing in court. Skipping this can get your case dismissed."
    ),
    'lupon': (
        "**Lupong Tagapamayapa — Barangay Peace Committee (RA 7160)**\n\n"
        "The Lupong Tagapamayapa is the body that implements the Katarungang Pambarangay "
        "(barangay justice system). It is composed of the **Punong Barangay** (as Chair) "
        "and **10–20 community members** appointed by the Punong Barangay.\n\n"
        "**Functions:**\n"
        "• Mediates and conciliates disputes between community members\n"
        "• Forms **Pangkat ng Tagapagkasundo** panels for unresolved cases\n"
        "• Enforces Amicable Settlements reached between disputing parties\n"
        "• Issues **Certificate to File Action** when conciliation fails\n\n"
        "**Process:** File complaint → Punong Barangay mediates (3 days) → "
        "Pangkat conciliates (30 days) → Amicable Settlement or Certificate to File Action\n\n"
        "For the full step-by-step guide, ask about **Katarungang Pambarangay**."
    ),
    'cybercrime': (
        "**Cybercrime Prevention Act of 2012 (Republic Act 10175)**\n\n"
        "RA 10175 penalizes crimes committed using computers, the internet, and "
        "other electronic devices.\n\n"
        "**Covered offenses:**\n"
        "• **Cyber libel** — defamatory posts online (6 years 1 day to 12 years imprisonment)\n"
        "• **Cyberbullying** and online harassment\n"
        "• **Online scams** and cyber estafa (fraud)\n"
        "• **Unauthorized computer access** (hacking)\n"
        "• **Identity theft** and phishing\n"
        "• **Online child pornography** (higher penalties)\n\n"
        "**Penalties:** Generally 1 degree higher than the equivalent offline crime under the RPC.\n\n"
        "**How to report cybercrime:**\n"
        "1. **PNP Anti-Cybercrime Group (ACG):** File at the nearest police station or Camp Crame. "
        "Hotline: (02) 8723-0401\n"
        "2. **NBI Cybercrime Division:** Taft Avenue, Manila. Hotline: (02) 8523-8231\n"
        "3. **Preserve all evidence:** screenshots, chat logs, URLs, transaction records\n"
        "4. For online harassment, your barangay can issue an initial documentation certificate\n\n"
        "**Note:** Cybercrime cases are handled by PNP-ACG or NBI at the city level, "
        "not at the barangay level. The barangay can assist with documentation."
    ),
    'dangerous drugs': (
        "**Comprehensive Dangerous Drugs Act of 2002 (Republic Act 9165)**\n\n"
        "RA 9165 governs the prevention, control, and penalization of illegal drug "
        "activities in the Philippines.\n\n"
        "**Key offenses and penalties:**\n"
        "• **Possession** of illegal drugs: 12 years to life imprisonment (based on quantity)\n"
        "• **Sale or trafficking:** Life imprisonment (reclusion perpetua)\n"
        "• **Possession of drug paraphernalia:** 6 months to 4 years\n"
        "• **Use of illegal drugs:** 6 months minimum; first offenders → mandatory rehabilitation\n\n"
        "**Barangay Anti-Drug Abuse Council (BADAC):**\n"
        "Every barangay has a BADAC to monitor, prevent, and report drug activity "
        "in the community.\n\n"
        "**How to report illegal drug activity:**\n"
        "1. Report to the **Barangay Captain** or **BADAC** — you may request confidentiality\n"
        "2. File at the nearest **Police Station**\n"
        "3. Call **PDEA Hotline: 1-800-10-PDEA-ko (7332-56)** or **PNP Hotline: 117**\n\n"
        "**Drug surrenderees:** Under PDEA's Oplan Tokhang, voluntary surrenderees are "
        "referred to rehabilitation, not prosecuted. Contact your barangay to surrender safely.\n\n"
        "The barangay is legally required to report suspected drug activity to the PNP "
        "within 24 hours of discovery."
    ),
    'magna carta for women': (
        "**Magna Carta of Women (Republic Act 9710)**\n\n"
        "RA 9710 guarantees the rights, empowerment, and participation of women "
        "in all spheres of Philippine society.\n\n"
        "**Key rights under RA 9710:**\n"
        "• **Equal opportunities** in employment, education, and government service — "
        "no discrimination based on sex\n"
        "• **Equal pay** — same wages as men for the same work and position\n"
        "• **Maternity leave** — at least 60 days paid leave (105 days under RA 11210)\n"
        "• **Protection from gender-based violence** — see RA 9262 (VAWC) for details\n"
        "• **Anti-sexual harassment** in workplaces, schools, and training institutions\n"
        "• **Women's property rights** — equal right to own, acquire, and register property\n"
        "• **Free reproductive health services** from government health centers\n"
        "• **Political participation** — at least 40% representation in third-level "
        "government bodies\n\n"
        "**Barangay obligations under RA 9710:**\n"
        "• Maintain a **VAW (Violence Against Women) Desk** staffed by a trained officer\n"
        "• Issue **Barangay Protection Orders (BPO)** within 24 hours for VAWC cases\n"
        "• Provide assistance, documentation, and referral for women survivors of violence\n\n"
        "**To report violations or seek help:**\n"
        "1. Visit your **Barangay VAW Desk** — available 24/7 for emergencies\n"
        "2. Contact the **Philippine Commission on Women (PCW):** (02) 8735-1654\n"
        "3. Call **DSWD Hotline 1343** for emergency shelter and assistance\n"
        "4. For violence or threat, call **911** or go to the nearest police station"
    ),
    'magna cartas': (
        "**Magna Cartas in Philippine Law — Overview**\n\n"
        "There are several Magna Cartas in the Philippines, each protecting a specific group:\n\n"
        "**1. Magna Carta for Persons with Disability (RA 7277, as amended)**\n"
        "• 20% discount on medicines, medical services, transportation, and restaurants\n"
        "• Free PWD ID, priority lanes in all establishments, scholarship programs\n\n"
        "**2. Magna Carta of Women (RA 9710)**\n"
        "• Equal rights in employment, education, and healthcare\n"
        "• Protection from gender-based violence and discrimination\n"
        "• Maternity leave, equal pay, property rights\n\n"
        "**3. Magna Carta for Public School Teachers (RA 4670)**\n"
        "• Security of tenure, professional development, and fair compensation\n"
        "• Free legal service for cases arising from official duties\n\n"
        "**4. Magna Carta for Public Health Workers (RA 7305)**\n"
        "• Hazard pay, housing allowance, health insurance for government health workers\n\n"
        "**5. Magna Carta for Small Farmers (RA 9700 / CARP Extension)**\n"
        "• Agrarian reform rights and agricultural land distribution\n\n"
        "Which specific Magna Carta would you like to know more about? Just ask!"
    ),
    'physical assault': (
        "**Physical Injuries and Assault under Philippine Law (Revised Penal Code)**\n\n"
        "Under the **Revised Penal Code (RPC)**, hitting, slapping, or physically harming "
        "another person is a criminal offense. Penalties depend on the severity of injury.\n\n"
        "**Penalties by severity:**\n"
        "• **Serious Physical Injuries (RPC Art. 263):** Victim loses a body part or is "
        "incapacitated for 91+ days → **6 months to 12 years imprisonment**\n"
        "• **Less Serious Physical Injuries (RPC Art. 265):** Incapacity of 10–30 days → "
        "**Arresto mayor (1–6 months)** imprisonment\n"
        "• **Slight Physical Injuries (RPC Art. 266):** A single slap, punch, or minor harm "
        "with no lasting injury → **Up to 30 days jail** and/or ₱200 fine\n\n"
        "**For a single slap or punch with no lasting injury:**\n"
        "This is **Slight Physical Injuries** — the victim can file a complaint at the "
        "barangay. The offender may face up to 30 days in jail and/or ₱200 fine.\n\n"
        "**Barangay process:**\n"
        "1. The victim files a complaint at the **Barangay Hall**\n"
        "2. The **Lupong Tagapamayapa** calls both parties within **3 days** for mediation\n"
        "3. If settled → **Amicable Settlement** signed (legally binding)\n"
        "4. If no settlement → **Certificate to File Action** issued to bring case to court\n\n"
        "**If you committed the act:** Cooperate with barangay mediation. Willingness to "
        "settle and pay damages can prevent criminal prosecution for minor injuries.\n\n"
        "**If you were the victim:** Go to a doctor and get a **Medico-Legal Certificate** "
        "as evidence. Report to the barangay or police immediately."
    ),
}

# ─── Tagalog versions of legal topic answers ───────────────────────────────────
_LEGAL_TOPIC_ANSWERS_TL: Dict[str, str] = {
    'vawc': (
        "**Batas Laban sa Karahasan ng Kababaihan at Kanilang mga Anak (Republic Act 9262)**\n\n"
        "Pinoprotektahan ng RA 9262 ang mga kababaihan at kanilang mga anak mula sa pisikal, "
        "sekswal, sikolohikal, at ekonomikong pang-aabuso ng asawa, dating asawa, o kasintahan.\n\n"
        "**Sino ang pinoprotektahan:**\n"
        "• Mga asawa o dating asawa\n"
        "• Mga babaeng nasa relasyon o dating relasyon\n"
        "• Mga babaeng may anak sa nang-aabuso\n\n"
        "**Uri ng pang-aabuso:** pisikal na karahasan, sekswal na pang-aabuso, sikolohikal na "
        "pang-aabuso (pagbabanta, pananakot), at ekonomikong kontrol (pagkontrol ng pera, "
        "pagwasak ng ari-arian).\n\n"
        "**Parusa:** 6 na buwan hanggang 12 taong pagkabilanggo, depende sa kalubhaan.\n\n"
        "**Paano humingi ng tulong sa barangay:**\n"
        "1. Pumunta sa **Barangay VAW Desk** — may VAW Desk ang bawat barangay ayon sa batas\n"
        "2. Humingi ng **Barangay Protection Order (BPO)** — kailangang maibigay sa loob ng "
        "24 na oras para mapigilan ang nang-aabuso na makipag-ugnayan sa inyo\n"
        "3. Para sa malubhang kaso, magsumbong sa **Pulis** o **Regional Trial Court**\n"
        "4. Tumawag sa **DSWD Hotline 1343** o **911** para sa emergency na tulong at kanlungan\n\n"
        "Hindi kailangan ng presensya ng nang-aabuso para makakuha ng Protection Order. "
        "Obligasyon ng barangay na kumilos agad sa inyong reklamo."
    ),
    'bullying': (
        "**Anti-Bullying Act ng 2013 (Republic Act 10627)**\n\n"
        "Inaatasan ng RA 10627 ang lahat ng elementarya at sekundaryang paaralan na magpatupad "
        "ng patakaran laban sa bullying para protektahan ang bawat mag-aaral.\n\n"
        "**Mga uri ng bullying:**\n"
        "• Pisikal: pagsuntok, pagtutulak, pag-atake\n"
        "• Pasalita: panlalait, pagbabanta, pang-uyam\n"
        "• Cyberbullying: pang-aabuso online, pagpapalat ng maling impormasyon\n"
        "• Sosyal: sadyang pagbubukod, pagpapalabas ng nakakahiyang bagay\n\n"
        "**Obligasyon ng paaralan:**\n"
        "1. Magpanatili ng nakasulat na Patakaran Laban sa Bullying\n"
        "2. Imbestigahan ang lahat ng reklamo sa loob ng **3 araw**\n"
        "3. Resolbahin ang kaso at magpataw ng angkop na parusa sa loob ng **10 araw**\n"
        "4. Irehistro ang bawat insidente sa Bullying Incident Report Book\n"
        "5. Abisuhan ang mga magulang ng bully at ng biktima\n\n"
        "**Paano mag-ulat ng bullying:**\n"
        "1. Iulat sa **Class Adviser** o **Principal** na may detalye ng insidente\n"
        "2. Kung hindi kumilos ang paaralan, eskalahan sa **Schools Division Superintendent (DepEd)**\n"
        "3. Para sa cyberbullying na may banta, iulat din sa **PNP Anti-Cybercrime Group**\n"
        "4. Kung menor de edad ang nang-aasar sa komunidad, maaaring mag-file ng reklamo sa barangay"
    ),
    'magna carta': (
        "**Magna Carta para sa Mga Taong may Kapansanan (Republic Act 7277, na sinusugan)**\n\n"
        "Ang RA 7277 (sinusugan ng RA 9442 at RA 10524) ay nagbibigay ng mga karapatan at "
        "pribilehiyo sa mga Pilipinong may kapansanan.\n\n"
        "**Mga pangunahing benepisyo:**\n"
        "• **20% diskwento** sa gamot, medikal/dental na serbisyo, hotel, restoran, "
        "recreational center, at lokal na transportasyon\n"
        "• **5% diskwento** sa mga pangunahing pangangailangan\n"
        "• Ang mga diskwento ay **VAT-exempt**\n"
        "• Priority lane sa lahat ng opisina ng gobyerno, ospital, at establisyimento\n"
        "• Libreng edukasyon sa publiko; scholarship para sa PWD\n"
        "• Sa ilalim ng RA 10524, dapat maglaan ang gobyerno ng **1% ng mga posisyon** para sa PWD\n\n"
        "**Paano makakuha ng PWD ID (libre):**\n"
        "1. Pumunta sa **Barangay Hall** o **City/Municipal Social Welfare Office (CSWDO)**\n"
        "2. Dalhin: medikal na sertipiko, valid ID, 2 passport-size na larawan, birth certificate\n"
        "3. Punan ang PWD Registration Form\n"
        "4. Ang ID ay ibinibigay sa loob ng 3–7 araw ng trabaho\n\n"
        "Ang PWD ID ay nare-renew taon-taon at valid sa buong Pilipinas."
    ),
    'solo parent': (
        "**Batas para sa Kapakanan ng Nag-iisang Magulang (Republic Act 8972)**\n\n"
        "Ang RA 8972 ay nagbibigay ng mga benepisyo at suporta sa mga nag-iisang magulang.\n\n"
        "**Sino ang kwalipikado:**\n"
        "• Magulang na namatay, nakakulong, o umalis ang asawa ng ≥1 taon\n"
        "• Babaeng nanganak nang walang kasal at nag-aalaga ng anak\n"
        "• Magulang na may pisikal o mental na kapansanan ang asawa\n"
        "• Kamag-anak na nag-aalaga ng batang ulila\n\n"
        "**Mga benepisyo:**\n"
        "• **Flexible na oras ng trabaho** — 1 oras/araw na adjustment mula sa employer\n"
        "• **7 araw na bayad na parental leave** bawat taon\n"
        "• Tulong pinansyal at scholarship para sa solo parent at mga anak\n"
        "• Priority sa programang pabahay ng gobyerno (Pag-IBIG, NHA)\n"
        "• Tulong medikal mula sa DSWD at lokal na pamahalaan\n\n"
        "**Paano makakuha ng Solo Parent ID:**\n"
        "1. Pumunta sa **City/Municipal Social Welfare and Development Office (CSWDO)**\n"
        "2. Dalhin: birth certificate ng anak, patunay ng solo parent status "
        "(death certificate, court order, o **sertipikasyon ng barangay**), valid ID, larawan\n"
        "3. Magparehistro at punan ang Solo Parent Registration Form\n"
        "4. Ang ID ay libre at valid ng 1 taon (nare-renew taon-taon)\n\n"
        "Ang **barangay ay maaaring mag-issue ng sertipikasyon** na kailangan para sa pagpaparehistro."
    ),
    'senior citizen': (
        "**Expanded Senior Citizens Act (Republic Act 9994)**\n\n"
        "Ang RA 9994 ay nagbibigay ng mga benepisyo at pribilehiyo sa lahat ng Pilipinong "
        "may **60 taon pataas**.\n\n"
        "**Mga pangunahing benepisyo:**\n"
        "• **20% diskwento + VAT exemption** sa: gamot, medikal/dental, hotel, restoran, "
        "transportasyon, at recreational center\n"
        "• **Libreng medikal at dental na serbisyo** sa ospital at klinika ng gobyerno\n"
        "• **Libreng bakuna** (flu at pneumococcal) sa health center ng gobyerno\n"
        "• **Priority lane** sa LAHAT ng establisyimento, opisina, at ospital\n"
        "• **₱500/buwan na social pension** para sa mahihirap na senior citizen (DSWD)\n"
        "• **10% diskwento sa kuryente, tubig, at telepono** "
        "(kung ang account ay nasa pangalan ng senior citizen)\n\n"
        "**Paano makakuha ng OSCA ID (libre):**\n"
        "1. Pumunta sa **Office for Senior Citizens Affairs (OSCA)** sa City/Municipal Hall\n"
        "2. Dalhin: birth certificate o baptismal record, valid ID, barangay clearance, 2 larawan\n"
        "3. Punan ang registration form\n"
        "4. Ang ID ay ibinibigay sa loob ng 1–3 araw ng trabaho\n\n"
        "Tinutulungan ng **barangay ang mga senior citizen** na makuha ang kanilang mga benepisyo."
    ),
    'katarungang pambarangay': (
        "**Katarungang Pambarangay — Sistemang Hustisya ng Barangay (RA 7160, Kabanata 7)**\n\n"
        "Ang Katarungang Pambarangay (KP) ay ang sistemang pangkomunidad ng paglutas ng "
        "alitan sa antas ng barangay sa pamamagitan ng medyasyon — nang hindi pumupunta sa korte.\n\n"
        "**Mga alitang sakop:**\n"
        "• Alitan ng mga kapitbahay (ingay, hangganan ng lupa, pagkasira ng ari-arian)\n"
        "• Menor na pisikal na pinsala at oral na paninirang-puri\n"
        "• Maliit na utang at simpleng usapin sa kontrata\n"
        "• Karamihan sa sibil at kriminal na kaso kung magkaparehong residente ng iisang barangay\n\n"
        "**Hakbang-hakbang na proseso:**\n"
        "1. **Mag-file ng reklamo** sa Barangay Hall — irerehistro ng Lupon Secretary\n"
        "2. **Ang Punong Barangay ay mag-memedya** — parehong partido ay tatawagin sa loob ng **3 araw**\n"
        "3. Kung nabigo ang medyasyon, isang **Pangkat ng Tagapagkasundo** (3 miyembro) ang itatayo\n"
        "4. Ang Pangkat ay may **30 araw** (palawig ng 15 araw) para makapag-areglo\n"
        "5. Kung matagumpay → **Amicable Settlement** na may puwersa ng hatol ng korte\n"
        "6. Kung nabigo → **Certificate to File Action** na nagpapahintulot sa korte\n\n"
        "**Mahalaga:** Para sa karamihang alitan sa pagitan ng mga residente ng iisang barangay, "
        "**kailangan munang dumaan sa KP** bago pumunta sa korte."
    ),
    'lupon': (
        "**Lupong Tagapamayapa — Barangay Peace Committee (RA 7160)**\n\n"
        "Ang Lupong Tagapamayapa ang katawan na nagpapatupad ng Katarungang Pambarangay. "
        "Binubuo ito ng **Punong Barangay** (bilang Tagapangulo) at **10–20 miyembro ng komunidad** "
        "na hinirang ng Punong Barangay.\n\n"
        "**Mga tungkulin:**\n"
        "• Nagme-medya at nagko-konsilia ng mga alitan sa komunidad\n"
        "• Nagtatayo ng **Pangkat ng Tagapagkasundo** para sa hindi naresolusyong kaso\n"
        "• Nagpapatupad ng Amicable Settlement sa pagitan ng mga nagtatalo\n"
        "• Nag-i-issue ng **Certificate to File Action** kung nabigo ang konsiliasyon\n\n"
        "**Proseso:** Mag-file ng reklamo → Punong Barangay mag-memedya (3 araw) → "
        "Pangkat mag-kokonsilia (30 araw) → Amicable Settlement o Certificate to File Action\n\n"
        "Para sa buong gabay, itanong tungkol sa **Katarungang Pambarangay**."
    ),
    'cybercrime': (
        "**Cybercrime Prevention Act ng 2012 (Republic Act 10175)**\n\n"
        "Ang RA 10175 ay nagpaparusa ng mga krimen na nagagawa sa pamamagitan ng "
        "kompyuter, internet, at iba pang elektronikong kagamitan.\n\n"
        "**Mga sakop na paglabag:**\n"
        "• **Cyber libel** — mapanirang post online (6 taon 1 araw hanggang 12 taon)\n"
        "• **Cyberbullying** at online na pang-aabuso\n"
        "• **Online scam** at cyber estafa (panloloko)\n"
        "• **Unauthorized na pag-access** (hacking)\n"
        "• **Identity theft** at phishing\n"
        "• **Online child pornography** (mas mataas na parusa)\n\n"
        "**Parusa:** Sa pangkalahatan, isang antas na mas mataas kaysa sa offline na katumbas "
        "sa ilalim ng Revised Penal Code.\n\n"
        "**Paano mag-ulat ng cybercrime:**\n"
        "1. **PNP Anti-Cybercrime Group (ACG):** Sa pinakamalapit na istasyon ng pulis. "
        "Hotline: (02) 8723-0401\n"
        "2. **NBI Cybercrime Division:** Taft Avenue, Maynila. Hotline: (02) 8523-8231\n"
        "3. **Pangalagaan ang ebidensya:** screenshots, chat logs, URLs, resibo\n"
        "4. Para sa online harassment, ang barangay ay maaaring mag-issue ng sertipikasyon\n\n"
        "**Tandaan:** Ang mga kaso ng cybercrime ay hinahawakan ng PNP-ACG o NBI, "
        "hindi ng barangay. Maaaring tumulong ang barangay sa dokumentasyon."
    ),
    'dangerous drugs': (
        "**Comprehensive Dangerous Drugs Act ng 2002 (Republic Act 9165)**\n\n"
        "Ang RA 9165 ay namamahala sa pag-iwas, kontrol, at pagpaparusa ng "
        "mga illegal na aktibidad kaugnay ng droga.\n\n"
        "**Mga pangunahing paglabag at parusa:**\n"
        "• **Pagtatago ng droga:** 12 taon hanggang habangbuhay (depende sa dami)\n"
        "• **Pagbebenta o trafficking:** Habangbuhay na pagkabilanggo (reclusion perpetua)\n"
        "• **Pagtatago ng gamit sa droga:** 6 na buwan hanggang 4 na taon\n"
        "• **Paggamit ng droga:** Minimum 6 na buwan; unang nagkasala → sapilitang rehabilitasyon\n\n"
        "**Barangay Anti-Drug Abuse Council (BADAC):**\n"
        "Ang bawat barangay ay may BADAC para subaybayan, pigilan, at iulat "
        "ang aktibidad ng droga sa komunidad.\n\n"
        "**Paano mag-ulat ng illegal na droga:**\n"
        "1. Iulat sa **Barangay Captain** o **BADAC** — maaari kayong humingi ng konfidensyalidad\n"
        "2. Magsumbong sa pinakamalapit na **Istasyon ng Pulis**\n"
        "3. Tumawag sa **PDEA Hotline: 1-800-10-PDEA-ko** o **PNP Hotline: 117**\n\n"
        "**Mga nagsu-surrender:** Ang mga nagvo-voluntaryong mag-surrender ay ipinadadala sa "
        "rehabilitasyon, hindi inuusig. Makipag-ugnayan sa inyong barangay.\n\n"
        "Ang barangay ay legal na obligadong iulat ang pinaghihinalaang aktibidad ng droga "
        "sa PNP sa loob ng 24 na oras."
    ),
    'magna carta for women': (
        "**Magna Carta ng Kababaihan (Republic Act 9710)**\n\n"
        "Tinitiyak ng RA 9710 ang mga karapatan, kapangyarihan, at pakikilahok ng kababaihan "
        "sa lahat ng larangan ng lipunan sa Pilipinas.\n\n"
        "**Mga pangunahing karapatan:**\n"
        "• **Pantay na pagkakataon** sa trabaho, edukasyon, at serbisyong pampubliko — "
        "walang diskriminasyon batay sa kasarian\n"
        "• **Pantay na sahod** — parehong bayad para sa parehong trabaho\n"
        "• **Maternity leave** — hindi bababa sa 60 araw na may bayad (105 araw sa RA 11210)\n"
        "• **Proteksyon mula sa karahasan** — tingnan ang RA 9262 (VAWC) para sa detalye\n"
        "• **Proteksyon laban sa sexual harassment** sa trabaho at paaralan\n"
        "• **Karapatang mag-ari ng ari-arian** nang pantay sa mga lalaki\n"
        "• **Libreng reproductive health services** mula sa mga health center ng gobyerno\n"
        "• **Pulitikal na pakikilahok** — hindi bababa sa 40% representasyon sa gobyerno\n\n"
        "**Obligasyon ng barangay:**\n"
        "• Magpanatili ng **VAW Desk** na may sanay na kawani\n"
        "• Mag-issue ng **Barangay Protection Order (BPO)** sa loob ng 24 na oras\n"
        "• Magbigay ng tulong at referral sa mga kababaihang biktima ng karahasan\n\n"
        "**Paano humingi ng tulong:**\n"
        "1. Pumunta sa **Barangay VAW Desk** — bukas para sa emergency\n"
        "2. Makipag-ugnayan sa **Philippine Commission on Women:** (02) 8735-1654\n"
        "3. Tumawag sa **DSWD Hotline 1343** para sa emergency na tulong\n"
        "4. Para sa karahasan o banta, tumawag sa **911** o pumunta sa pulis"
    ),
    'magna cartas': (
        "**Mga Magna Carta sa Pilipinas — Pangkalahatang-tanaw**\n\n"
        "Mayroong ilang Magna Carta sa Pilipinas, bawat isa ay nagpoprotekta ng partikular na grupo:\n\n"
        "**1. Magna Carta para sa Taong may Kapansanan (RA 7277)**\n"
        "• 20% diskwento sa gamot, medikal na serbisyo, transportasyon, at restoran\n"
        "• Libreng PWD ID, priority lane, scholarship\n\n"
        "**2. Magna Carta ng Kababaihan (RA 9710)**\n"
        "• Pantay na karapatan sa trabaho, edukasyon, at pangangalagang pangkalusugan\n"
        "• Proteksyon mula sa karahasan at diskriminasyon\n\n"
        "**3. Magna Carta para sa Guro sa Pampublikong Paaralan (RA 4670)**\n"
        "• Seguridad ng trabaho, propesyonal na pag-unlad, at makatarungang kompensasyon\n\n"
        "**4. Magna Carta para sa Manggagawang Pangkalusugan (RA 7305)**\n"
        "• Hazard pay, allowance, at insurance para sa mga health worker ng gobyerno\n\n"
        "**5. Magna Carta para sa Maliliit na Magsasaka (RA 9700 / CARP)**\n"
        "• Mga karapatang agraryano at pamamahagi ng lupa\n\n"
        "Alin sa mga Magna Carta ang nais ninyong malaman nang higit pa? Itanong lamang!"
    ),
    'physical assault': (
        "**Pisikal na Pinsala at Pag-atake sa ilalim ng Pilipinong Batas (Revised Penal Code)**\n\n"
        "Sa ilalim ng **Revised Penal Code (RPC)**, ang pagsampal, pagsuntok, o pisikal na "
        "pinsala sa ibang tao ay isang krimen. Ang parusa ay nakasalalay sa kalubhaan ng pinsala.\n\n"
        "**Parusa ayon sa kalubhaan:**\n"
        "• **Seryosong Pisikal na Pinsala (RPC Art. 263):** Nawala ang bahagi ng katawan o "
        "hindi makakilos ng 91+ araw → **6 buwan hanggang 12 taon sa bilangguan**\n"
        "• **Mas Magaan na Pisikal na Pinsala (RPC Art. 265):** Hindi makakilos ng 10–30 araw → "
        "**1 hanggang 6 na buwan** sa bilangguan\n"
        "• **Magaan na Pisikal na Pinsala (RPC Art. 266):** Isang sampal, suntok, o menor na "
        "pinsala → **Hanggang 30 araw** at/o ₱200 na multa\n\n"
        "**Para sa isang sampal o suntok lamang:**\n"
        "Ito ay **Magaan na Pisikal na Pinsala** — maaaring mag-file ng reklamo ang biktima "
        "sa barangay. Ang nagkasala ay maaaring pagmultahin ng ₱200 o ikulong ng hanggang 30 araw.\n\n"
        "**Proseso sa barangay:**\n"
        "1. Mag-file ng reklamo sa **Barangay Hall**\n"
        "2. Ang **Lupong Tagapamayapa** ay tatawag sa parehong partido sa loob ng **3 araw**\n"
        "3. Kung may kasunduan → **Amicable Settlement** na may bisa ng hatol ng korte\n"
        "4. Kung walang kasunduan → **Certificate to File Action** para dalhin sa korte\n\n"
        "**Kung ikaw ang biktima:** Pumunta sa doktor at kumuha ng **Medico-Legal Certificate** "
        "bilang ebidensya. Iulat sa barangay o pulis kaagad."
    ),
}


# Maps all keys in _LEGAL_ABBREVIATIONS → the matching key in _LEGAL_TOPIC_ANSWERS (or None)
_ABBR_TO_TOPIC: Dict[str, Optional[str]] = {
    'vawc':                                     'vawc',
    'ra 9262':                                  'vawc',
    'ra 7610':                                  None,
    'ra 11313':                                 None,
    'ra 10627':                                 'bullying',
    'anti-bullying':                            'bullying',
    'bullying act':                             'bullying',
    'bullying':                                 'bullying',
    'magna carta':                              'magna carta',
    'magna carta for persons with disability':  'magna carta',
    'magna carta for pwd':                      'magna carta',
    'pwd':                                      'magna carta',
    'persons with disabilities':                'magna carta',
    'solo parent':                              'solo parent',
    'ra 8972':                                  'solo parent',
    'senior citizen':                           'senior citizen',
    'ra 9994':                                  'senior citizen',
    'katarungang pambarangay':                  'katarungang pambarangay',
    'lupon':                                    'lupon',
    'lupong tagapamayapa':                      'lupon',
    'rpc':                                      None,
    'revised penal code':                       None,
    'civil code':                               None,
    'family code':                              None,
    'ra 7160':                                  'katarungang pambarangay',
    'local government code':                    'katarungang pambarangay',
    'anti-hazing':                              None,
    'ra 11053':                                 None,
    'cybercrime':                               'cybercrime',
    'ra 10175':                                 'cybercrime',
    'data privacy':                             None,
    'ra 9165':                                  'dangerous drugs',
    'dangerous drugs':                          'dangerous drugs',
    # Magna Carta of Women
    'magna carta of women':                     'magna carta for women',
    'magna carta for women':                    'magna carta for women',
    'magna carta ng kababaihan':                'magna carta for women',
    'magna carta women':                        'magna carta for women',
    'ra 9710':                                  'magna carta for women',
    # Multiple magna cartas overview
    'magna cartas':                             'magna cartas',
    'different magna carta':                    'magna cartas',
    'all magna carta':                          'magna cartas',
    # Individual magna cartas — resolved when user picks a number from the list
    # (must be longer than 'magna carta' so they're checked first by length sort)
    'magna carta for public school teachers':   'magna cartas',
    'magna carta for public health workers':    'magna cartas',
    'magna carta for small farmers':            'magna cartas',
    'ra 4670':                                  'magna cartas',
    'ra 7305':                                  'magna cartas',
    # Debt / civil disputes → handled by Katarungang Pambarangay
    'debt':                                     'katarungang pambarangay',
    'utang':                                    'katarungang pambarangay',
    'hindi nagbabayad':                         'katarungang pambarangay',
    'ayaw magbayad':                            'katarungang pambarangay',
    'hindi magbabayad':                         'katarungang pambarangay',
    'doesnt pay':                               'katarungang pambarangay',
    "doesn't pay":                              'katarungang pambarangay',
    'civil dispute':                            'katarungang pambarangay',
    'neighbour dispute':                        'katarungang pambarangay',
    'neighbor dispute':                         'katarungang pambarangay',
    'alitan':                                   'katarungang pambarangay',
    'away sa kapitbahay':                       'katarungang pambarangay',
    'dispute with neighbor':                    'katarungang pambarangay',
    # Physical assault / injuries
    'physical assault':                         'physical assault',
    'physical injury':                          'physical assault',
    'physical injuries':                        'physical assault',
    'smacked':                                  'physical assault',
    'smack':                                    'physical assault',
    'punched someone':                          'physical assault',
    'slapped someone':                          'physical assault',
    'hit someone':                              'physical assault',
    'slight physical':                          'physical assault',
    'less serious physical':                    'physical assault',
    'serious physical':                         'physical assault',
}


# ─── Model generation ──────────────────────────────────────────────────────────
def _generate_with_model(
    user_input: str,
    history: List[Dict] = None,
    context: str = None,
) -> str:
    """
    Generates a detailed response using the BLA_Gemma3 model.

    Gemma 3 constraints:
    - No 'system' role — embed system prompt in first user message
    - Strict user→assistant alternation
    - apply_chat_template may return BatchEncoding or raw tensor

    Args:
        user_input: The user's (possibly expanded) query.
        history: Conversation history list of {role, content} dicts.
        context: Optional relevant knowledge (FAQ answer or topic info) injected
                 into the system prompt so the model generates a grounded response.
    """
    import torch

    # ── Sanitize history ──────────────────────────────────────────────────────
    cleaned: List[Dict] = []
    last_role: Optional[str] = None
    for h in (history or [])[-8:]:
        raw_role = h.get("role", "")
        role = "assistant" if raw_role in ("bot", "assistant") else "user"
        content = h.get("content", "").strip()
        if not content:
            continue
        if role == last_role:
            cleaned[-1] = {"role": role, "content": content}
        else:
            cleaned.append({"role": role, "content": content})
            last_role = role
    while cleaned and cleaned[0]["role"] == "assistant":
        cleaned.pop(0)
    cleaned = cleaned[-4:]

    # ── Build active system prompt (with optional knowledge context) ──────────
    # Truncate context to keep input token count manageable for the 1B model.
    # A full _LEGAL_TOPIC_ANSWERS entry (~1200 chars) would make generation very
    # slow; 400 chars gives the model the key facts without blowing up input size.
    base_system = MASTER_SYSTEM_PROMPT
    if context:
        base_system += (
            "\n\nKEY LEGAL REFERENCE (use as grounding — respond conversationally):\n"
            + context[:400]
        )

    # ── Language detection & instruction injection ────────────────────────────
    user_is_tagalog = _is_tagalog(user_input)
    if user_is_tagalog:
        active_system = (
            base_system +
            "\n\nMAPAKHALAGAHAN: Ang gumagamit ay nagsulat sa Filipino/Tagalog. "
            "KAILANGAN mong sumagot nang BUO sa Filipino/Tagalog. "
            "Huwag gumamit ng Ingles maliban sa mga legal na termino."
        )
        user_input = (
            "IMPORTANTENG TAGUBILIN: Sagutin ang tanong na ito sa Filipino/Tagalog LAMANG. "
            "Magbigay ng detalyadong sagot.\n\n" + user_input
        )
    else:
        active_system = base_system

    # ── Build message list ────────────────────────────────────────────────────
    messages: List[Dict] = []
    if cleaned:
        for i, msg in enumerate(cleaned):
            if i == 0 and msg["role"] == "user":
                messages.append({
                    "role": "user",
                    "content": f"{active_system}\n\n{msg['content']}",
                })
            else:
                messages.append({"role": msg["role"], "content": msg["content"]})
        messages.append({"role": "user", "content": user_input})
    else:
        messages = [{"role": "user", "content": f"{active_system}\n\n{user_input}"}]

    if messages[-1]["role"] != "user":
        messages.append({"role": "user", "content": user_input})

    # ── Tokenize ──────────────────────────────────────────────────────────────
    encoded = tokenizer.apply_chat_template(
        messages,
        add_generation_prompt=True,
        return_tensors="pt",
    )
    if hasattr(encoded, "input_ids"):
        input_ids = encoded.input_ids.to(model.device)
        # Explicit attention mask avoids the "pad==eos" warning and ensures
        # the model attends to every token correctly
        attention_mask = (
            encoded.attention_mask.to(model.device)
            if hasattr(encoded, "attention_mask")
            else torch.ones_like(encoded.input_ids).to(model.device)
        )
    else:
        input_ids = encoded.to(model.device)
        attention_mask = torch.ones_like(input_ids)

    # ── Generate (with hard timeout to prevent client-side TimeoutException) ──
    # model.generate() is CPU-bound and can take >2 minutes with large inputs.
    # Running it in a thread and capping at _GENERATION_TIMEOUT seconds means
    # the caller gets "" on timeout and falls back to the raw context string,
    # so the Flutter client never hits its 2-minute network timeout.
    def _do_generate():
        with torch.no_grad():
            return model.generate(
                input_ids=input_ids,
                attention_mask=attention_mask,
                max_new_tokens=256,
                do_sample=True,
                temperature=0.3,
                top_p=0.9,
                repetition_penalty=1.15,
                pad_token_id=tokenizer.eos_token_id,
                use_cache=True,
            )

    try:
        future = _model_executor.submit(_do_generate)
        output_ids = future.result(timeout=_GENERATION_TIMEOUT)
    except _cf.TimeoutError:
        logger.warning(
            f"Model generation timed out after {_GENERATION_TIMEOUT}s — "
            "caller will use raw context fallback"
        )
        return ""
    except Exception as gen_err:
        logger.error(f"Model generation error: {gen_err}")
        return ""

    new_tokens = output_ids[0][input_ids.shape[-1]:]
    return tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


# ─── HuggingFace Inference API (cloud fallback) ────────────────────────────────
def call_huggingface_api(prompt: str) -> Optional[str]:
    """
    Low-level call to the HuggingFace Inference API.

    Args:
        prompt: Pre-formatted prompt string (Gemma 3 chat template).

    Returns:
        Generated text string, or None if the call fails or returns an
        unexpected format.
    """
    logger.info("🔥 CALLING HUGGINGFACE API 🔥")
    try:
        resp = _http.post(
            f"https://api-inference.huggingface.co/models/{os.environ.get('HF_MODEL_ID', _HF_MODEL_ID)}",
            headers={
                "Authorization": f"Bearer {os.environ.get('HF_API_TOKEN', '')}",
                "x-wait-for-model": "true",
            },
            json={
                "inputs": prompt,
                "parameters": {
                    "max_new_tokens": 200,
                    "temperature": 0.7,
                    "return_full_text": False,
                },
            },
            timeout=120,
        )
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, list) and data:
            return data[0].get("generated_text", "").strip() or None
        if isinstance(data, dict) and "error" in data:
            logger.error(f"HF API error: {data['error']}")
        return None
    except Exception as exc:
        logger.error(f"HF API request failed: {exc}")
        return None


def _generate_with_hf_api(
    user_input: str,
    history: List[Dict] = None,
    context: str = None,
) -> str:
    """
    Calls the HuggingFace Inference API when the local model is not loaded.
    Builds the same prompt structure as _generate_with_model() so responses
    are consistent between local and cloud inference.
    """
    # ── Sanitize history (mirrors _generate_with_model) ───────────────────────
    cleaned: List[Dict] = []
    last_role: Optional[str] = None
    for h in (history or [])[-8:]:
        raw_role = h.get("role", "")
        role = "assistant" if raw_role in ("bot", "assistant") else "user"
        content = h.get("content", "").strip()
        if not content:
            continue
        if role == last_role:
            cleaned[-1] = {"role": role, "content": content}
        else:
            cleaned.append({"role": role, "content": content})
            last_role = role
    while cleaned and cleaned[0]["role"] == "assistant":
        cleaned.pop(0)
    cleaned = cleaned[-4:]

    # ── Build system prompt ────────────────────────────────────────────────────
    base_system = MASTER_SYSTEM_PROMPT
    if context:
        base_system += (
            "\n\nKEY LEGAL REFERENCE (use as grounding — respond conversationally):\n"
            + context[:400]
        )

    user_is_tagalog = _is_tagalog(user_input)
    if user_is_tagalog:
        active_system = (
            base_system +
            "\n\nMAPAKHALAGAHAN: Ang gumagamit ay nagsulat sa Filipino/Tagalog. "
            "KAILANGAN mong sumagot nang BUO sa Filipino/Tagalog. "
            "Huwag gumamit ng Ingles maliban sa mga legal na termino."
        )
        user_input = (
            "IMPORTANTENG TAGUBILIN: Sagutin ang tanong na ito sa Filipino/Tagalog LAMANG. "
            "Magbigay ng detalyadong sagot.\n\n" + user_input
        )
    else:
        active_system = base_system

    # ── Build messages ─────────────────────────────────────────────────────────
    messages: List[Dict] = []
    if cleaned:
        for i, msg in enumerate(cleaned):
            if i == 0 and msg["role"] == "user":
                messages.append({
                    "role": "user",
                    "content": f"{active_system}\n\n{msg['content']}",
                })
            else:
                messages.append({"role": msg["role"], "content": msg["content"]})
        messages.append({"role": "user", "content": user_input})
    else:
        messages = [{"role": "user", "content": f"{active_system}\n\n{user_input}"}]

    if messages[-1]["role"] != "user":
        messages.append({"role": "user", "content": user_input})

    # ── Format as Gemma 3 chat template ───────────────────────────────────────
    # Gemma 3 has no "system" role; system prompt is embedded in the first user turn.
    parts = ["<bos>"]
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        parts.append(f"<start_of_turn>{role}\n{msg['content']}<end_of_turn>\n")
    parts.append("<start_of_turn>model\n")
    prompt = "".join(parts)

    # ── Call HF Inference API ─────────────────────────────────────────────────
    return call_huggingface_api(prompt) or ""


def _generate(
    user_input: str,
    history: List[Dict] = None,
    context: str = None,
) -> str:
    """Generate a response using the best available backend.

    Priority:
      1. Local model (if loaded) – return result if non-empty
      2. HF Inference API (if token present) – return result if non-empty
      3. FAQ/knowledge search fallback – never return None

    This central helper is called by the higher-level logic in ``generate_chat_response``
    so that we can encapsulate routing and make failure modes simpler.
    """
    # try local model first
    if model_loaded:
        try:
            resp = _generate_with_model(user_input, history, context)
            if resp:
                return resp
        except Exception as e:
            logger.warning(f"Local model generation failed: {e}")
    # next, attempt HF API if a token is configured
    hf_token_now = os.environ.get("HF_API_TOKEN", "")
    if hf_token_now:
        try:
            resp = _generate_with_hf_api(user_input, history, context)
            if resp:
                return resp
        except Exception as e:
            logger.warning(f"HF API generation failed: {e}")
    # final fallback: knowledge base (FAQ/dataset)
    kb = _search_knowledge(user_input)
    return kb or ""


def _resolve_numbered_choice(user_input: str, history: List[Dict]) -> Optional[str]:
    """
    If the user replies with just a number (1–9), look at the last bot message
    for a matching numbered list item and return its text.
    E.g. "5" after a magna carta list → "Magna Carta for Small Farmers (RA 9700 / CARP Extension)"
    """
    text = user_input.strip()
    if not re.match(r'^\d$', text):
        return None
    n = int(text)
    if n < 1 or n > 9:
        return None
    for h in reversed(history or []):
        if h.get('role') not in ('bot', 'assistant'):
            continue
        content = h.get('content', '')
        # Match "**N. Some text**" or "N. Some text"
        m = re.search(rf'(?:^|\n)\**{n}\.\s+\**(.+?)(?:\*\*)?(?:\n|$)', content)
        if m:
            return m.group(1).strip().strip('*').strip()
    return None


def _extract_question_from_correction(text: str) -> Optional[str]:
    """Extract the actual question from a correction/clarification message."""
    patterns = [
        r'i said[,:]?\s+(.{5,})',
        r'i asked[,:]?\s+(.{5,})',
        r'my question (?:is|was)[,:]?\s+(.{5,})',
        r'i (?:mean|meant)[,:]?\s+(.{5,})',
        r'i was asking (?:about|for)[,:]?\s+(.{5,})',
    ]
    t_lower = text.lower().strip()
    for pat in patterns:
        m = re.search(pat, t_lower)
        if m:
            q = m.group(m.lastindex).strip()
            if len(q) > 5:
                return q
    # Fallback: use the last substantive sentence
    sentences = [s.strip() for s in re.split(r'[.!?]+', text) if s.strip() and len(s.strip()) > 8]
    skip = {'i didnt ask about that', "that's not what i asked", 'wrong answer', 'please answer my question'}
    if len(sentences) >= 2:
        for s in reversed(sentences):
            if s.lower() not in skip and len(s) > 10:
                return s
    return None


# ─── Public API ────────────────────────────────────────────────────────────────
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
        # Resolve single-digit choice against last bot's numbered list first
        # (e.g. user types "5" after a magna carta list → replace with item text)
        resolved = _resolve_numbered_choice(user_input, history or [])
        if resolved:
            logger.info(f"Resolved numbered choice {user_input!r} → {resolved!r}")
            user_input = resolved

        # Normalize shorthand / typos before any processing
        user_input = _normalize_typos(user_input)

        # Detect language once — used throughout for choosing TL vs EN responses
        user_is_tagalog = _is_tagalog(user_input)

        intent = _detect_intent(user_input)
        logger.info(f"Intent={intent!r} | lang={'tl' if user_is_tagalog else 'en'} | input={user_input!r}")

        # Routing intents → instant structured response (language-aware)
        if intent in _ROUTED:
            if intent == 'complaint' and _match(user_input, _DRUG_PATS):
                key = 'complaint_drug'
            else:
                key = intent
            if user_is_tagalog and key in _ROUTED_TL:
                return _ROUTED_TL[key]
            return _ROUTED[key]

        # ── Translation request ───────────────────────────────────────────────
        if intent == 'translate':
            # Find the last user message that was NOT a translation request
            original = None
            for h in reversed(history or []):
                if h.get('role') not in ('user', 'human'):
                    continue
                q = _normalize_typos(h.get('content', '').strip())
                if q and not _match(q, _TRANSLATE_PATS):
                    original = q
                    break

            if original:
                orig_lower = original.lower().strip()
                # Check if original query was a known legal topic → use TL version
                # If model loaded: use TL version as context for generation
                # If model not loaded: return TL version directly
                tl_ctx = None
                for abbr in sorted(_ABBR_TO_TOPIC, key=len, reverse=True):
                    topic_key = _ABBR_TO_TOPIC.get(abbr)
                    if topic_key and abbr in orig_lower:
                        tl = _LEGAL_TOPIC_ANSWERS_TL.get(topic_key)
                        if tl:
                            logger.info(f"Translation: TL version of {topic_key!r}")
                            if model_loaded:
                                tl_ctx = tl
                            else:
                                return tl, None
                        break
                # Check KB for Tagalog version if no topic DB hit
                if not tl_ctx:
                    tl_query = f"tagalog {original}"
                    tl_answer = _search_knowledge(tl_query, threshold=0.30)
                    if tl_answer:
                        if model_loaded:
                            tl_ctx = tl_answer
                        else:
                            return tl_answer, None
                # Generate in Tagalog with context (grounded + conversational)
                if model_loaded or _hf_available:
                    tl_input = (
                        "SAGUTIN SA TAGALOG LAMANG. Huwag gumamit ng Ingles maliban sa "
                        "mga legal na termino. Tanong: " + original
                    )
                    response = _generate(tl_input, history, context=tl_ctx)
                    if response:
                        return response, None

            return (
                "Para makakuha ng sagot sa Tagalog, mangyaring itanong ang inyong "
                "katanungan sa Filipino (hal.: 'Ano ang VAWC?' o 'Paano mag-file ng reklamo?'). "
                "Sasagutin ko kayo nang buo sa Filipino.",
                None,
            )

        # ── Meta-command: simplify / elaborate / summarize ────────────────────
        if intent == 'meta':
            last_bot = None
            for h in reversed(history or []):
                if h.get('role') in ('bot', 'assistant'):
                    last_bot = h.get('content', '').strip()
                    if last_bot:
                        break
            if not last_bot:
                return (
                    "I'm happy to help! What topic would you like me to explain? "
                    "You can ask about barangay laws, documents, or your legal rights.",
                    None,
                )
            if model_loaded or _hf_available:
                meta_input = (
                    "Re-explain the following in clear, well-organized, easy-to-understand "
                    "language. Keep it concise but complete:\n\n" + last_bot
                )
                response = _generate(meta_input, [])
                if response:
                    return response, None
            # No-model fallback: extract the first meaningful block
            lines = [l.strip() for l in last_bot.split('\n') if l.strip()]
            summary = '\n'.join(lines[:6]) if lines else last_bot[:500]
            return (
                "Here's the key information:\n\n" + summary +
                "\n\nFeel free to ask about any specific part for more details!",
                None,
            )

        # ── Correction: user says previous answer was wrong ───────────────────
        if intent == 'correction':
            extracted = _extract_question_from_correction(user_input)
            if extracted and extracted.lower() != user_input.lower():
                logger.info(f"Correction detected — re-processing: {extracted!r}")
                extracted_norm = _normalize_typos(extracted)
                extr_lower = extracted_norm.lower().strip()
                for abbr in sorted(_ABBR_TO_TOPIC, key=len, reverse=True):
                    topic_key = _ABBR_TO_TOPIC.get(abbr)
                    if topic_key and abbr in extr_lower:
                        if user_is_tagalog:
                            tl = _LEGAL_TOPIC_ANSWERS_TL.get(topic_key)
                            if tl:
                                return tl, None
                        return _LEGAL_TOPIC_ANSWERS[topic_key], None
                kb = _search_knowledge(extracted_norm)
                if kb:
                    return kb, None
                if model_loaded or _hf_available:
                    response = _generate(_expand_query(extracted_norm), history)
                    if response:
                        return response, None
            if user_is_tagalog:
                return (
                    "Paumanhin sa kalituhan! Maaari ba ninyong ulitin ang inyong tanong? "
                    "Nais kong matiyak na makabibigay ako ng tumpak na impormasyon.",
                    None,
                )
            return (
                "I apologize for the confusion! Could you please rephrase your question? "
                "I want to make sure I give you accurate information.",
                None,
            )

        # Enrich vague follow-ups with context from history
        enriched = _enrich_with_context(user_input, history or [])
        logger.info(f"Enriched: {enriched!r}")

        # ── Legal topic DB (instant, language-aware) ──────────────────────────
        lower_q = user_input.lower().strip()
        enriched_l = enriched.lower().strip()
        combined = f"{lower_q} {enriched_l}"

        for abbr in sorted(_ABBR_TO_TOPIC, key=len, reverse=True):
            topic_key = _ABBR_TO_TOPIC.get(abbr)
            if topic_key and abbr in combined:
                logger.info(f"Topic DB hit: {abbr!r} → {topic_key!r}")
                if user_is_tagalog:
                    tl = _LEGAL_TOPIC_ANSWERS_TL.get(topic_key)
                    if tl:
                        return tl, None
                return _LEGAL_TOPIC_ANSWERS[topic_key], None

        # ── Knowledge base (FAQ + dataset) — instant answer ───────────────────
        kb = _search_knowledge(enriched) if enriched != user_input else None
        if not kb:
            kb = _search_knowledge(user_input)
        if kb:
            logger.info("KB hit.")
            return kb, None

        # ── Generation: local model or HF API ────────────────────────────────
        expanded = _expand_query(enriched)
        if expanded != enriched:
            logger.info(f"Query expanded for generation: {expanded[:80]!r}…")

        # Re-read token at call time — module-level _hf_available may be stale
        # if Railway injects env vars after the module was first imported.
        _hf_token_now = os.environ.get("HF_API_TOKEN", "")
        _hf_model_now = os.environ.get("HF_MODEL_ID", _HF_MODEL_ID)
        logger.info(
            f"Generation routing: model_loaded={model_loaded} "
            f"hf_available={bool(_hf_token_now)} "
            f"model_id={_hf_model_now}"
        )

        if model_loaded:
            logger.info("Using local model for generation.")
            response = _generate_with_model(expanded, history)
            if response:
                return response, None
        elif _hf_token_now:
            prompt = (
                f"<bos><start_of_turn>user\n"
                f"{MASTER_SYSTEM_PROMPT}\n\n{expanded}"
                f"<end_of_turn>\n<start_of_turn>model\n"
            )
            logger.info(f"🔥 CALLING HUGGINGFACE API 🔥 | Prompt: {prompt[:200]!r}…")
            response = call_huggingface_api(prompt)
            if response:
                return response, None
        else:
            logger.warning(
                "No generation backend available "
                "(model_loaded=False, HF_API_TOKEN not set). Using fallback."
            )

        # ── Generic fallback (language-aware) ─────────────────────────────────
        if user_is_tagalog:
            return (
                "Paumanhin, wala akong tiyak na impormasyon doon. "
                "Espesyalista ako sa mga usapin ng barangay. Narito ang mga maaari mong itanong:\n\n"
                "📋 *Mga Dokumento*: barangay clearance, residency, indigency, good moral\n"
                "⚖️ *Mga Reklamo*: karahasan, pagnanakaw, ingay, alitan sa kapitbahay\n"
                "🏛️ *Mga Batas*: VAWC, anti-bullying, droga, senior citizen, PWD, solo parent\n"
                "📝 *Mga Proseso*: blotter, protection order, conciliation, lupon\n"
                "👥 *Mga Serbisyo*: 4Ps, Sangguniang Kabataan, barangay tanod\n\n"
                "Maaari kang magtanong sa Filipino o Ingles.",
                None,
            )
        return (
            "I don't have specific information on that. "
            "I specialize in barangay legal matters. Here's what you can ask me:\n\n"
            "📋 *Documents*: clearance, residency, indigency, good moral character\n"
            "⚖️ *Complaints*: violence, theft, noise, neighbor disputes\n"
            "🏛️ *Laws & Rights*: VAWC, anti-bullying, drugs, senior citizen, PWD, solo parent\n"
            "📝 *Processes*: blotter, protection order, conciliation, lupon\n"
            "👥 *Services*: 4Ps, Sangguniang Kabataan, barangay tanod\n\n"
            "Feel free to ask in Filipino or English!",
            None,
        )

    except Exception as e:
        logger.error(f"Error in generate_chat_response: {e}", exc_info=True)
        return (
            "I apologize, I encountered an issue processing your request. "
            "Please try again, or contact the barangay office directly for immediate assistance.",
            None,
        )


# ─── Endpoint-ready wrapper ────────────────────────────────────────────────────
def chat_response(sender: int, message: str) -> dict:
    """
    Accept { sender: int, message: str } and return { response, enriched, sender }.

    Called by POST /chats/ai. The local model is used exclusively — no HF online calls.
    """
    logger.info(f"[CHAT_REQUEST] sender={sender} message={message!r}")

    # Normalise typos and expand short legal queries before passing to the model
    normalised = _normalize_typos(message)
    enriched   = _expand_query(normalised)
    logger.info(f"[ENRICHED_INPUT] {enriched!r}")

    response_text, _ui_action = generate_chat_response(enriched)
    logger.info(f"[MODEL_OUTPUT] sender={sender} response={response_text!r}")

    return {
        "response": response_text,
        "enriched": enriched,
        "sender":   sender,
    }
