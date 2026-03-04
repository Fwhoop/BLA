"""
validate_sft_data.py
────────────────────
Validates the SFT training JSONL before fine-tuning.

Checks:
  1. Every line is parseable JSON.
  2. Every record has all three required fields: instruction, input, output.
  3. No field is empty or whitespace-only.
  4. Prints a topic breakdown and length statistics.

Usage:
    python validate_sft_data.py                          # default: sft_training_data.jsonl
    python validate_sft_data.py path/to/custom_data.jsonl
"""

import io
import json
import os
import sys
from typing import Dict, List, Tuple

# Force UTF-8 output on Windows terminals (cp1252 can't encode box-drawing chars)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

REQUIRED_FIELDS = {"instruction", "input", "output"}

# Keywords used to auto-classify samples by topic
_TOPIC_MAP = [
    ("dog bite",              "Dog Bite (RA 9482)"),
    ("anti-rabies",           "Dog Bite (RA 9482)"),
    ("vawc",                  "VAWC (RA 9262)"),
    ("violence against women","VAWC (RA 9262)"),
    ("noise",                 "Noise Complaint"),
    ("debt",                  "Unpaid Debt"),
    ("utang",                 "Unpaid Debt"),
    ("boundary",              "Boundary Dispute"),
    ("trespass",              "Trespassing"),
    ("slander",               "Slander / Oral Defamation"),
    ("oral defamation",       "Slander / Oral Defamation"),
    ("clearance",             "Barangay Clearance"),
    ("mediation",             "Mediation / Settlement"),
    ("settlement",            "Mediation / Settlement"),
    ("refusal",               "Out-of-Scope Refusal"),
    ("outside barangay",      "Out-of-Scope Refusal"),
    ("beyond barangay",       "Out-of-Scope Refusal"),
]


def _classify(sample: dict) -> str:
    # Include output so refusal samples (whose topic appears there) are classified correctly
    text = (sample["instruction"] + " " + sample["input"] + " " + sample["output"]).lower()
    for keyword, topic in _TOPIC_MAP:
        if keyword in text:
            return topic
    return "Uncategorised"


def validate(path: str) -> Tuple[List[str], List[dict]]:
    """
    Parse the JSONL file once and return (errors, valid_samples).
    Callers get both the error list and the parsed objects in one pass —
    no need to re-open the file for statistics.
    """
    errors: List[str] = []
    samples: List[dict] = []
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, start=1):
            raw = raw.strip()
            if not raw:
                continue  # skip blank lines

            # ── Check 1: valid JSON ──────────────────────────────────────────
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError as exc:
                errors.append(f"  Line {lineno:>3}: INVALID JSON — {exc}")
                continue

            # ── Check 2: all required fields present ─────────────────────────
            missing = REQUIRED_FIELDS - set(obj.keys())
            if missing:
                errors.append(f"  Line {lineno:>3}: Missing field(s) — {sorted(missing)}")
                continue

            # ── Check 3: no empty values ─────────────────────────────────────
            line_ok = True
            for field in REQUIRED_FIELDS:
                if not str(obj[field]).strip():
                    errors.append(f"  Line {lineno:>3}: Empty field '{field}'")
                    line_ok = False

            if line_ok:
                samples.append(obj)

    return errors, samples


def report(path: str) -> None:
    """Print a full validation + statistics report."""
    if not os.path.exists(path):
        print(f"ERROR: File not found — {path}")
        sys.exit(1)

    print(f"\nValidating: {path}")
    print("─" * 60)

    # Single file read — validate() returns both errors and parsed samples
    errors, samples = validate(path)

    if errors:
        print(f"VALIDATION FAILED — {len(errors)} error(s) found:\n")
        for e in errors:
            print(e)
        sys.exit(1)

    total = len(samples)

    # Length statistics (no second file read needed)
    out_lens = [len(s["output"]) for s in samples]
    inp_lens = [len(s["input"]) for s in samples]
    avg_out  = sum(out_lens) / total
    max_out  = max(out_lens)
    min_out  = min(out_lens)
    avg_inp  = sum(inp_lens) / total

    # Topic breakdown
    topic_counts: Dict[str, int] = {}
    for s in samples:
        topic = _classify(s)
        topic_counts[topic] = topic_counts.get(topic, 0) + 1

    print(f"  Status  : ALL {total} samples PASSED validation")
    print(f"  Fields  : {sorted(REQUIRED_FIELDS)} — all present and non-empty\n")
    print(f"  Output length   avg={avg_out:.0f}  min={min_out}  max={max_out} chars")
    print(f"  Input  length   avg={avg_inp:.0f} chars\n")
    print("  Topic breakdown:")
    for topic, count in sorted(topic_counts.items(), key=lambda x: x[0]):
        bar = "█" * count
        print(f"    {topic:<35} {bar} ({count})")

    print("\n  JSONL is ready for fine-tuning.\n")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "sft_training_data.jsonl"
    # Support relative path from any working directory
    if not os.path.isabs(target):
        here = os.path.dirname(os.path.abspath(__file__))
        target = os.path.join(here, target)
    report(target)
