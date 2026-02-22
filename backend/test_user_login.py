"""
Test script to verify user login credentials
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db import SessionLocal
from app.models import User
import bcrypt

def test_user_login():
    db = SessionLocal()
    try:
        email = "user@legalaid.com"
        password = "password123"
        
        user = db.query(User).filter(User.email == email).first()
        
        if not user:
            print(f"❌ User not found: {email}")
            return False
        
        print(f"✅ User found: {email}")
        print(f"   Username: {user.username}")
        print(f"   Role: {user.role}")
        print(f"   Is Active: {user.is_active}")
        print(f"   Barangay ID: {user.barangay_id}")
        
        # Test password verification
        try:
            result = bcrypt.checkpw(
                password.encode('utf-8'),
                user.hashed_password.encode('utf-8')
            )
            
            if result:
                print(f"✅ Password verification: SUCCESS")
                print(f"   Password '{password}' is correct!")
                return True
            else:
                print(f"❌ Password verification: FAILED")
                print(f"   Password '{password}' does not match!")
                print(f"   Password hash: {user.hashed_password[:50]}...")
                return False
        except Exception as e:
            print(f"❌ Password verification error: {e}")
            return False
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    finally:
        db.close()

if __name__ == "__main__":
    test_user_login()


