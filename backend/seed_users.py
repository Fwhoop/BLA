"""
Script to seed initial users in the database
Run this with: python seed_users.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db import SessionLocal
from app.models import User, Barangay
from passlib.context import CryptContext
from datetime import datetime

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

def seed_users():
    db = SessionLocal()
    try:
        barangay = db.query(Barangay).filter(Barangay.name == "Barangay 1").first()
        if not barangay:
            barangay = Barangay(name="Barangay 1")
            db.add(barangay)
            db.commit()
            db.refresh(barangay)
            print(f"Created barangay: {barangay.name} (ID: {barangay.id})")
        
        admin_email = "admin@legalaid.com"
        admin = db.query(User).filter(User.email == admin_email).first()
        if not admin:
            admin = User(
                email=admin_email,
                username="admin",
                hashed_password=get_password_hash("admin123"),
                first_name="Admin",
                last_name="User",
                role="admin",
                barangay_id=barangay.id,
                is_active=True,
                created_at=datetime.utcnow()
            )
            db.add(admin)
            print(f"Created admin user: {admin_email}")
        else:
            print(f"Admin user already exists: {admin_email}")
        
        superadmin_email = "superadmin@legalaid.com"
        superadmin = db.query(User).filter(User.email == superadmin_email).first()
        if not superadmin:
            superadmin = User(
                email=superadmin_email,
                username="superadmin",
                hashed_password=get_password_hash("superadmin123"),
                first_name="Super",
                last_name="Admin",
                role="superadmin",
                barangay_id=None,
                is_active=True,
                created_at=datetime.utcnow()
            )
            db.add(superadmin)
            print(f"Created superadmin user: {superadmin_email}")
        else:
            print(f"Superadmin user already exists: {superadmin_email}")
        
        user_email = "user@legalaid.com"
        user = db.query(User).filter(User.email == user_email).first()
        if not user:
            user = User(
                email=user_email,
                username="user",
                hashed_password=get_password_hash("password123"),
                first_name="Juan",
                last_name="Dela Cruz",
                role="user",
                barangay_id=barangay.id,
                is_active=True,
                created_at=datetime.utcnow()
            )
            db.add(user)
            print(f"Created regular user: {user_email}")
        else:
            print(f"Regular user already exists: {user_email}")
        
        db.commit()
        print("\n Users seeded successfully!")
        print("\nLogin credentials:")
        print("  Admin: admin@legalaid.com / admin123")
        print("  Superadmin: superadmin@legalaid.com / superadmin123")
        print("  User: user@legalaid.com / password123")
        
    except Exception as e:
        db.rollback()
        print(f" Error seeding users: {e}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed_users()

