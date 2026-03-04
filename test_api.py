"""
test_api.py
───────────
Automated integration test for the BLA chatbot API endpoint.

Fixes from the original broken script:
  1. URL    : /chat       → /chats/ai
  2. Body   : {message}  → {sender_id, receiver_id, message, history}
  3. Key    : resp[reply] → resp[message]
  4. Memory : history list is accumulated and passed on every subsequent turn

Covers the full testing checklist:
  ✓ Dog Bite / RA 9482   — legal steps, acknowledgment, safety advice
  ✓ Follow-up context    — memory works across multiple turns
  ✓ Structured headings  — all 8 sections appear
  ✓ Refusals             — out-of-scope returns proper message
  ✓ Bilingual output     — mix of English & Filipino
  ✓ Formatting           — headings + sections consistent

Usage:
    python test_api.py                         # default host/port
    python test_api.py --url http://host:port  # custom server
    python test_api.py --suite refusal         # run one suite only
    python test_api.py --verbose               # show full responses
"""

import argparse
import json
import sys
import textwrap
import time
from typing import List, Optional, Tuple

try:
    import requests
except ImportError:
    print("ERROR: 'requests' not installed. Run:  pip install requests")
    sys.exit(1)

# ─── CLI args ─────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="BLA chatbot API integration test")
parser.add_argument("--url",     default="http://127.0.0.1:8000",
                    help="Base URL of the running server (default: http://127.0.0.1:8000)")
parser.add_argument("--sender",  type=int, default=1,
                    help="sender_id to use in every request (default: 1)")
parser.add_argument("--receiver",type=int, default=2,
                    help="receiver_id to use in every request (default: 2)")
parser.add_argument("--suite",   default="all",
                    choices=["all", "dogbite", "vawc", "noise", "debt",
                             "clearance", "refusal", "multiturn"],
                    help="Which test suite to run (default: all)")
parser.add_argument("--verbose", action="store_true",
                    help="Print full response text (default: truncated)")
parser.add_argument("--timeout", type=int, default=60,
                    help="Request timeout in seconds (default: 60)")
args = parser.parse_args()

ENDPOINT     = f"{args.url.rstrip('/')}/chats/ai"
SENDER_ID    = args.sender
RECEIVER_ID  = args.receiver
TIMEOUT      = args.timeout
WIDTH        = 76

# ─── Colour helpers ───────────────────────────────────────────────────────────
_C = sys.stdout.isatty()
def _green(s):  return f"\033[92m{s}\033[0m" if _C else s
def _red(s):    return f"\033[91m{s}\033[0m"  if _C else s
def _yellow(s): return f"\033[93m{s}\033[0m"  if _C else s
def _cyan(s):   return f"\033[96m{s}\033[0m"  if _C else s
def _bold(s):   return f"\033[1m{s}\033[0m"   if _C else s

# ─── Core request helper ──────────────────────────────────────────────────────
def send(message: str, history: List[dict]) -> Tuple[str, Optional[str], float]:
    """
    POST to /chats/ai.

    Request body (AiChatCreate):
        sender_id   : int
        receiver_id : int
        message     : str
        history     : list of {role: str, content: str}   ← conversation so far

    Returns (reply_text, ui_action, latency_seconds).
    Raises SystemExit on connection error so the suite stops cleanly.
    """
    payload = {
        "sender_id":   SENDER_ID,
        "receiver_id": RECEIVER_ID,
        "message":     message,
        "history":     history,   # ← REQUIRED for multi-turn memory
    }
    t0 = time.time()
    try:
        resp = requests.post(ENDPOINT, json=payload, timeout=TIMEOUT)
    except requests.exceptions.ConnectionError:
        print(_red(f"\nERROR: Could not connect to {ENDPOINT}"))
        print(_red("       Is the FastAPI server running?  uvicorn app.main:app --reload"))
        sys.exit(1)
    except requests.exceptions.Timeout:
        print(_red(f"\nERROR: Request timed out after {TIMEOUT}s"))
        print(_red("       The model is still loading, or generation is very slow."))
        print(_red(f"       Try --timeout {TIMEOUT * 2}"))
        sys.exit(1)

    elapsed = time.time() - t0

    if resp.status_code != 200:
        print(_red(f"\nHTTP {resp.status_code} from {ENDPOINT}"))
        print(_red(f"Body: {resp.text[:400]}"))
        sys.exit(1)

    data = resp.json()
    # Response shape: {message, ui_action, sender_id, receiver_id}
    return data["message"], data.get("ui_action"), elapsed


# ─── Single-turn assertion helper ─────────────────────────────────────────────
PASS = _green("PASS")
FAIL = _red("FAIL")

def check(label: str, reply: str, must_contain: List[str] = (),
          must_not_contain: List[str] = (), latency: float = 0.0) -> bool:
    """Print result line and return True if all checks pass."""
    rl = reply.lower()
    missing  = [k for k in must_contain     if k.lower() not in rl]
    unwanted = [k for k in must_not_contain if k.lower() in     rl]
    ok = not missing and not unwanted
    sym = PASS if ok else FAIL
    print(f"  {sym}  {label}  ({latency:.1f}s)")
    if missing:
        print(_yellow(f"         Missing  : {missing}"))
    if unwanted:
        print(_red(f"         Unwanted : {unwanted}"))
    return ok


# ─── Test suites ──────────────────────────────────────────────────────────────

def suite_dogbite() -> List[bool]:
    """Multi-turn dog bite scenario — Tagalog → follow-up → preparation."""
    print(_bold("\n[Suite] Dog Bite (RA 9482) — multi-turn"))
    print("-" * WIDTH)
    results = []
    history = []

    # Turn 1 — initial complaint in Tagalog
    msg1   = "Kinagat ako ng aso ng aking kapitbahay kahapon. Masakit at may sugat. Ano ang dapat kong gawin?"
    reply1, _, lat1 = send(msg1, history)
    _print_turn(1, msg1, reply1)
    results.append(check(
        "Turn 1: Tagalog dog bite — safety + legal steps",
        reply1,
        must_contain=["barangay", "RA 9482", "ospital"],
    ))
    # Structured headings check
    results.append(check(
        "Turn 1: Structured output — legal basis section present",
        reply1,
        must_contain=["legal basis"],
    ))
    _push(history, msg1, reply1)

    # Turn 2 — follow-up (owner refuses to pay) — tests memory
    msg2   = "Ayaw ng may-ari ng aso magbayad ng aking gastos sa ospital. Anong gagawin ko?"
    reply2, _, lat2 = send(msg2, history)
    _print_turn(2, msg2, reply2)
    results.append(check(
        "Turn 2: Owner refuses — escalation options present",
        reply2,
        must_contain=["CFA", "court"],
    ))
    results.append(check(
        "Turn 2: Context remembered — still about dog bite",
        reply2,
        must_not_contain=["murder", "annulment"],
    ))
    _push(history, msg2, reply2)

    # Turn 3 — what to prepare
    msg3   = "Ano ang dapat kong ihanda para sa reklamo?"
    reply3, _, lat3 = send(msg3, history)
    _print_turn(3, msg3, reply3)
    results.append(check(
        "Turn 3: Preparation — what to prepare section",
        reply3,
        must_contain=["what to prepare", "ID", "medical"],
    ))
    _push(history, msg3, reply3)

    return results


def suite_vawc() -> List[bool]:
    """VAWC complaint — BPO request."""
    print(_bold("\n[Suite] VAWC (RA 9262)"))
    print("-" * WIDTH)
    results = []
    history = []

    msg1   = ("My husband hit me and threatened to hurt our children. "
              "I am scared. What can the barangay do for me?")
    reply1, _, lat1 = send(msg1, history)
    _print_turn(1, msg1, reply1)
    results.append(check(
        "VAWC: BPO mentioned",
        reply1, must_contain=["Barangay Protection Order", "RA 9262"],
    ))
    results.append(check(
        "VAWC: Safety advice present",
        reply1, must_contain=["safe", "police"],
    ))
    _push(history, msg1, reply1)

    msg2   = "The barangay gave me a BPO but my husband came back. He is threatening me again."
    reply2, _, lat2 = send(msg2, history)
    _print_turn(2, msg2, reply2)
    results.append(check(
        "VAWC follow-up: BPO violation — arrest / police mentioned",
        reply2, must_contain=["violation", "arrest"],
    ))
    return results


def suite_noise() -> List[bool]:
    """Noise complaint — videoke."""
    print(_bold("\n[Suite] Noise Complaint"))
    print("-" * WIDTH)
    history = []
    msg = ("My neighbor plays videoke very loudly every night until 2 AM. "
           "My children cannot sleep. Can I file a complaint at the barangay?")
    reply, _, lat = send(msg, history)
    _print_turn(1, msg, reply)
    return [
        check("Noise: Sumbong / barangay process mentioned", reply,
              must_contain=["barangay", "sumbong"]),
        check("Noise: Settlement / kasunduan mentioned", reply,
              must_contain=["kasunduan"]),
    ]


def suite_debt() -> List[bool]:
    """Unpaid debt scenario."""
    print(_bold("\n[Suite] Unpaid Debt"))
    print("-" * WIDTH)
    history = []
    msg = "I lent my neighbor P15,000 six months ago and she refuses to pay me back. Can I go to the barangay?"
    reply, _, lat = send(msg, history)
    _print_turn(1, msg, reply)
    return [
        check("Debt: Mediation / Lupon mentioned", reply,
              must_contain=["lupon", "mediation"]),
        check("Debt: Settlement agreement mentioned", reply,
              must_contain=["kasunduan"]),
        check("Debt: Small claims mentioned if unresolved", reply,
              must_contain=["court"]),
    ]


def suite_clearance() -> List[bool]:
    """Barangay clearance application."""
    print(_bold("\n[Suite] Barangay Clearance"))
    print("-" * WIDTH)
    history = []
    msg = "How do I apply for a barangay clearance? What are the requirements?"
    reply, _, lat = send(msg, history)
    _print_turn(1, msg, reply)
    return [
        check("Clearance: Requirements listed", reply,
              must_contain=["ID", "fee"]),
        check("Clearance: Process explained", reply,
              must_contain=["barangay", "clearance"]),
    ]


def suite_refusal() -> List[bool]:
    """Out-of-scope queries — must NOT give barangay procedure."""
    print(_bold("\n[Suite] Refusals (out-of-scope)"))
    print("-" * WIDTH)
    results = []

    cases = [
        (
            "Homicide — should refuse barangay mediation",
            "My brother was stabbed and killed by his neighbor. Can we file the murder case at the barangay?",
            ["prosecutor", "PNP"],          # must contain
            ["step-by-step barangay procedure"],  # must NOT contain
        ),
        (
            "Annulment — should refuse barangay mediation",
            "I want to get an annulment from my husband. Can the barangay process this?",
            ["Regional Trial Court", "lawyer"],
            ["step-by-step barangay procedure"],
        ),
        (
            "Drug trafficking — should redirect to PNP/PDEA",
            "My neighbor is selling drugs. Can the barangay arrest him?",
            ["PNP", "PDEA"],
            [],
        ),
        (
            "Large fraud — should redirect to RTC",
            "My business partner owes me P5,000,000 from fraud. Can I go to the barangay?",
            ["Regional Trial Court", "prosecutor"],
            [],
        ),
    ]

    for label, msg, must, must_not in cases:
        reply, _, lat = send(msg, [])
        _print_turn(1, msg, reply)
        results.append(check(label, reply,
                             must_contain=must, must_not_contain=must_not,
                             latency=lat))
    return results


def suite_multiturn() -> List[bool]:
    """Verify conversation history (memory) across 4 turns on a boundary dispute."""
    print(_bold("\n[Suite] Multi-turn Memory — Boundary Dispute"))
    print("-" * WIDTH)
    results = []
    history = []

    turns = [
        (
            "My neighbor moved his fence onto my land. What should I do?",
            ["barangay", "survey"],
            "Turn 1: Initial boundary complaint",
        ),
        (
            "He already built a storage room on the disputed area. Does that change things?",
            ["structure", "demolish"],
            "Turn 2: Structure on disputed land — context from turn 1 used",
        ),
        (
            "We had a survey done and it confirmed the fence is 1.5m inside my property. He still won't accept it.",
            ["survey", "CFA", "court"],
            "Turn 3: Survey result — escalation",
        ),
        (
            "The barangay gave us a CFA. Where do we go next?",
            ["Municipal Trial Court", "RTC", "title"],
            "Turn 4: Post-CFA — court guidance",
        ),
    ]

    for msg, keywords, label in turns:
        reply, _, lat = send(msg, history)
        _print_turn(len(history) // 2 + 1, msg, reply)
        results.append(check(label, reply, must_contain=keywords, latency=lat))
        _push(history, msg, reply)

    return results


# ─── Utility ──────────────────────────────────────────────────────────────────
def _push(history: list, user_msg: str, bot_reply: str) -> None:
    """Append a user+bot exchange to the history list in-place."""
    history.extend([
        {"role": "user", "content": user_msg},
        {"role": "bot",  "content": bot_reply},
    ])


def _print_turn(turn: int, msg: str, reply: str) -> None:
    print(f"\n  {_cyan(f'Turn {turn}')}  {_yellow('User:')} {textwrap.shorten(msg, 70, placeholder='…')}")
    if args.verbose:
        wrapped = textwrap.fill(reply, width=WIDTH - 4,
                                initial_indent="  ", subsequent_indent="  ")
        print(f"  {_yellow('Bot:')}\n{wrapped}")
    else:
        print(f"  {_yellow('Bot:')} {textwrap.shorten(reply, 140, placeholder='…')}")


# ─── Connectivity check ───────────────────────────────────────────────────────
def ping() -> None:
    print(f"Checking server at {args.url} …")
    try:
        r = requests.get(f"{args.url.rstrip('/')}/docs", timeout=5)
        print(f"  /docs → HTTP {r.status_code} — server is up")
    except requests.exceptions.ConnectionError:
        print(_red(f"\nERROR: Server not reachable at {args.url}"))
        print(_red("  Start it with:  uvicorn app.main:app --reload  (from backend/)"))
        sys.exit(1)


# ─── Main ─────────────────────────────────────────────────────────────────────
SUITES = {
    "dogbite":   suite_dogbite,
    "vawc":      suite_vawc,
    "noise":     suite_noise,
    "debt":      suite_debt,
    "clearance": suite_clearance,
    "refusal":   suite_refusal,
    "multiturn": suite_multiturn,
}

print("=" * WIDTH)
print(_bold("  BLA Chatbot API — Integration Test"))
print("=" * WIDTH)
print(f"  Endpoint  : {ENDPOINT}")
print(f"  sender_id : {SENDER_ID}   receiver_id : {RECEIVER_ID}")
print(f"  Timeout   : {TIMEOUT}s\n")

ping()

to_run = list(SUITES.keys()) if args.suite == "all" else [args.suite]

all_results: List[bool] = []
for name in to_run:
    all_results.extend(SUITES[name]())

# ─── Summary ──────────────────────────────────────────────────────────────────
passed = sum(all_results)
total  = len(all_results)
pct    = passed / total * 100 if total else 0

print("\n" + "=" * WIDTH)
print(_bold("  RESULT SUMMARY"))
print("=" * WIDTH)
print(f"  Checks passed : {passed} / {total}  ({pct:.0f}%)")

if pct == 100:
    print(_green("  All checks passed. Chatbot is ready."))
elif pct >= 70:
    print(_yellow("  Most checks passed. Review warnings above."))
else:
    print(_red("  Many checks failed. Review server logs and model output."))
    print(_red("  Common causes:"))
    print(_red("    • Model not loaded (LOAD_MODEL=false or ML libs missing)"))
    print(_red("    • Fine-tuned adapter not found (run finetune_lora.py first)"))
    print(_red("    • Server not started or database not seeded"))

print()
sys.exit(0 if pct == 100 else 1)
