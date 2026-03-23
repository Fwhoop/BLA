"""
Script to check what users exist in the database
Run this with: python check_users.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db import SessionLocal
from app.models import User

def check_users():
    db = SessionLocal()
    try:
        users = db.query(User).all()
        
        if not users:
            print("❌ No users found in the database!")
            print("\n💡 Run 'python seed_users.py' to create users.")
            return
        
        print(f"\n✅ Found {len(users)} user(s) in the database:\n")
        print("-" * 80)
        print(f"{'Email':<40} {'Username':<20} {'Role':<15} {'Active':<10}")
        print("-" * 80)
        
        for user in users:
            print(f"{user.email:<40} {user.username:<20} {user.role:<15} {str(user.is_active):<10}")
        
        print("-" * 80)
        
        # Check for specific accounts
        print("\n📋 Checking for specific accounts:")
        
        required_accounts = {
            'mysuperadmin@legalaid.com': 'mysuper123',
            'testuser@legalaid.com': 'testuser123',
            'testadmin@legalaid.com': 'testadmin123',
            'admin@legalaid.com': 'admin123',
            'user@legalaid.com': 'password123',
        }
        
        for email, password in required_accounts.items():
            user = db.query(User).filter(User.email == email).first()
            if user:
                print(f"  ✅ {email} - EXISTS")
            else:
                print(f"  ❌ {email} - NOT FOUND")
        
        print("\n💡 If accounts are missing, run 'python seed_users.py' to create them.")
        
    except Exception as e:
        print(f"❌ Error checking users: {e}")
        print("\n💡 Make sure your database is connected and .env file is configured.")
    finally:
        db.close()

if __name__ == "__main__":
    check_users()


