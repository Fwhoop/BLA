import os

try:
    from transformers import AutoTokenizer, AutoModelForCausalLM
    from sentence_transformers import SentenceTransformer
    import torch
    ML_AVAILABLE = True
except ImportError as e:
    print(f"ML libraries not available: {e}. Chatbot will use fallback responses.")
    ML_AVAILABLE = False

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "bla_chatbot_model")

sbert_model = None
tokenizer = None
model = None
model_loaded = False

if ML_AVAILABLE:
    try:
        if os.path.exists(MODEL_DIR):
            sbert_model = SentenceTransformer(MODEL_DIR)
            tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR, local_files_only=True)
            model = AutoModelForCausalLM.from_pretrained(MODEL_DIR, local_files_only=True, trust_remote_code=True)
            model_loaded = True
            print(f"Chatbot model loaded successfully from {MODEL_DIR}")
        else:
            print(f"Warning: Model directory not found at {MODEL_DIR}. Chatbot will use fallback responses.")
    except Exception as e:
        print(f"Warning: Could not load chatbot model: {e}. Chatbot will use fallback responses.")

def generate_chat_response(user_input: str) -> str:
    """
    Generates a human-readable response from the BLA chatbot model.
    Falls back to a simple response if model is not loaded.
    """
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        if not ML_AVAILABLE or not model_loaded or model is None:
            logger.info(f"Model not loaded, using fallback for: {user_input}")
            return f"Thank you for your message. I'm the Barangay Legal Aid chatbot. Currently, I'm being set up with advanced AI capabilities. Please contact the barangay office directly for immediate assistance."
        
        logger.info(f"Generating response with model for: {user_input}")
        inputs = tokenizer(user_input, return_tensors="pt")

        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_length=150,          
                num_beams=3,            
                no_repeat_ngram_size=2,  
                early_stopping=True
            )
        
        response = tokenizer.decode(outputs[0], skip_special_tokens=True)
        logger.info(f"Generated response: {response[:100]}")
        return response
    except Exception as e:
        logger.error(f"Error in generate_chat_response: {str(e)}", exc_info=True)
        return f"I apologize, but I encountered an error while processing your request. Please contact the barangay office directly for assistance."
