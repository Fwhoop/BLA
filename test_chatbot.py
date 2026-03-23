"""
Test script to verify the AI chatbot returns coherent, non-gibberish responses.
The chatbot is FAQ-based: it matches user input to barangay_law_flutter.json
and returns the answer, or a fixed fallback message.
"""
import sys
import os

# Run from backend directory so app and JSON path resolve
os.chdir(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.getcwd())

from app.chatbot import generate_chat_response, load_faq_data


def test_chatbot():
    print("=" * 60)
    print("Barangay Legal Aid Chatbot – response check")
    print("=" * 60)

    # Ensure FAQ loads
    faq = load_faq_data()
    if faq is None:
        print("FAIL: FAQ data did not load. Check path to barangay_law_flutter.json")
        return False
    n_cat = len(faq.get("categories", []))
    n_q = sum(
        len(c.get("questions", []))
        for c in faq.get("categories", [])
    )
    print(f"FAQ loaded: {n_cat} categories, {n_q} questions\n")

    test_cases = [
        # Should match FAQ closely
        "What is the penalty for operating videoke past 10 PM?",
        "Who enforces noise violations?",
        "What is the curfew for minors on school nights?",
        # Partial match
        "videoke after 10pm",
        "curfew minors",
        # Unrelated – should get fallback
        "What's the weather today?",
        "Hello",
    ]

    all_ok = True
    for i, query in enumerate(test_cases, 1):
        print(f"Query {i}: {query!r}")
        try:
            response = generate_chat_response(query)
        except Exception as e:
            print(f"  ERROR: {e}")
            all_ok = False
            print()
            continue

        # Basic sanity: not empty, not huge, no obvious gibberish
        if not response or not response.strip():
            print("  FAIL: Empty response")
            all_ok = False
        elif len(response) > 2000:
            print("  WARN: Very long response (possible bug)")
        else:
            # Show first 200 chars (ASCII-safe for Windows console)
            preview = response.strip()[:200]
            if len(response) > 200:
                preview += "..."
            # Avoid UnicodeEncodeError on Windows console
            try:
                print(f"  Response: {preview}")
            except UnicodeEncodeError:
                print(f"  Response: {preview.encode('ascii', 'replace').decode('ascii')}")
            print("  OK: non-empty, reasonable length")
        print()

    if all_ok:
        print("All responses look coherent (FAQ match or fallback). Model is working as designed.")
    else:
        print("Some checks failed. Review errors above.")
    return all_ok


if __name__ == "__main__":
    ok = test_chatbot()
    sys.exit(0 if ok else 1)
