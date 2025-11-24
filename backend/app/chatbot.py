import os
import json
from typing import Optional
from difflib import SequenceMatcher

# Load JSON data once at startup
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
JSON_FILE = os.path.join(os.path.dirname(BASE_DIR), "barangay_law_flutter.json")
faq_data = None

def load_faq_data():
    """Load FAQ data from JSON file."""
    global faq_data
    if faq_data is not None:
        return faq_data
    
    try:
        if os.path.exists(JSON_FILE):
            with open(JSON_FILE, 'r', encoding='utf-8') as f:
                faq_data = json.load(f)
            print(f"FAQ data loaded successfully from {JSON_FILE}")
            print(f"Loaded {len(faq_data.get('categories', []))} categories")
            return faq_data
        else:
            print(f"Warning: JSON file not found at {JSON_FILE}")
            return None
    except Exception as e:
        print(f"Error loading FAQ data: {e}")
        return None

def similarity_score(str1: str, str2: str) -> float:
    """Calculate similarity between two strings."""
    return SequenceMatcher(None, str1.lower(), str2.lower()).ratio()

def find_best_match(user_input: str, threshold: float = 0.5) -> Optional[str]:
    """
    Search for the best matching question in the FAQ data.
    Returns the answer if a match is found above the threshold.
    """
    data = load_faq_data()
    if data is None:
        return None
    
    user_input_lower = user_input.lower().strip()
    best_match = None
    best_score = 0.0
    
    # Search through all categories and questions
    for category in data.get('categories', []):
        for question_obj in category.get('questions', []):
            question = question_obj.get('question', '')
            answer = question_obj.get('answer', '')
            
            question_lower = question.lower().strip()
            
            # Check for exact match first
            if question_lower == user_input_lower:
                return answer
            
            # Calculate similarity score
            score = similarity_score(user_input, question)
            
            # Also check if user input contains keywords from the question
            question_words = set(question_lower.split())
            input_words = set(user_input_lower.split())
            common_words = question_words.intersection(input_words)
            if len(common_words) > 0:
                # Boost score if there are common words
                word_score = len(common_words) / max(len(question_words), len(input_words))
                score = max(score, word_score * 0.8)
            
            if score > best_score:
                best_score = score
                best_match = answer
    
    # Return best match if above threshold
    if best_score >= threshold and best_match:
        return best_match
    
    return None

def generate_chat_response(user_input: str) -> str:
    """
    Generates a response by searching the FAQ JSON file.
    Falls back to a default response if no match is found.
    """
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        logger.info(f"Searching FAQ for: {user_input}")
        
        # Search for matching answer
        answer = find_best_match(user_input, threshold=0.5)
        
        if answer:
            logger.info(f"Found matching answer in FAQ")
            return answer
        else:
            logger.info(f"No matching answer found, using default response")
            # Try a lower threshold for partial matches
            answer = find_best_match(user_input, threshold=0.3)
            if answer:
                return answer
            
            # Default response if no match found
            return "I'm here to help with Barangay Legal Aid questions. I couldn't find a specific answer to your question. Please try rephrasing your question, or contact the barangay office directly for assistance. You can also browse the categories to find relevant questions."
    
    except Exception as e:
        logger.error(f"Error in generate_chat_response: {str(e)}", exc_info=True)
        return "I apologize, but I encountered an error while processing your request. Please contact the barangay office directly for assistance."
