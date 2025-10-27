from transformers import AutoTokenizer, AutoModelForCausalLM
from sentence_transformers import SentenceTransformer
import torch, os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "bla_chatbot_model")

sbert_model = SentenceTransformer(MODEL_DIR)

tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR, local_files_only=True)
model = AutoModelForCausalLM.from_pretrained(MODEL_DIR, local_files_only=True, trust_remote_code=True)

def generate_chat_response(user_input: str) -> str:
    """
    Generates a human-readable response from the BLA chatbot model.
    """
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
    return response
