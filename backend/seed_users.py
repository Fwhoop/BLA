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
from datetime import datetime, timezone

# Use the same password context as auth router
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    """Hash password using passlib (compatible with auth router)"""
    try:
        return pwd_context.hash(password)
    except Exception as e:
        # Fallback to bcrypt directly if passlib fails
        import bcrypt
        password_bytes = password.encode('utf-8')
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(password_bytes, salt)
        return hashed.decode('utf-8')

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
                created_at=datetime.now(timezone.utc)
            )
            db.add(admin)
            print(f"Created admin user: {admin_email}")
        else:
            print(f"Admin user already exists: {admin_email}")
        
        # Create the main superadmin account (only one allowed)
        mysuperadmin_email = "mysuperadmin@legalaid.com"
        mysuperadmin = db.query(User).filter(User.email == mysuperadmin_email).first()
        if not mysuperadmin:
            mysuperadmin = User(
                email=mysuperadmin_email,
                username="mysuperadmin",
                hashed_password=get_password_hash("mysuper123"),
                first_name="My",
                last_name="SuperAdmin",
                role="superadmin",
                barangay_id=None,
                is_active=True,
                created_at=datetime.now(timezone.utc)
            )
            db.add(mysuperadmin)
            print(f"Created superadmin user: {mysuperadmin_email}")
        else:
            print(f"Superadmin user already exists: {mysuperadmin_email}")
        
        # Create test accounts
        testuser_email = "testuser@legalaid.com"
        testuser = db.query(User).filter(User.email == testuser_email).first()
        if not testuser:
            testuser = User(
                email=testuser_email,
                username="testuser",
                hashed_password=get_password_hash("testuser123"),
                first_name="Test",
                last_name="User",
                role="user",
                barangay_id=barangay.id,
                is_active=True,
                created_at=datetime.now(timezone.utc)
            )
            db.add(testuser)
            print(f"Created test user: {testuser_email}")
        else:
            print(f"Test user already exists: {testuser_email}")
        
        testadmin_email = "testadmin@legalaid.com"
        testadmin = db.query(User).filter(User.email == testadmin_email).first()
        if not testadmin:
            testadmin = User(
                email=testadmin_email,
                username="testadmin",
                hashed_password=get_password_hash("testadmin123"),
                first_name="Test",
                last_name="Admin",
                role="admin",
                barangay_id=barangay.id,
                is_active=True,
                created_at=datetime.now(timezone.utc)
            )
            db.add(testadmin)
            print(f"Created test admin: {testadmin_email}")
        else:
            print(f"Test admin already exists: {testadmin_email}")
        
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
                created_at=datetime.now(timezone.utc)
            )
            db.add(user)
            print(f"Created regular user: {user_email}")
        else:
            print(f"Regular user already exists: {user_email}")
        
        db.commit()
        print("\n✅ Users seeded successfully!")
        print("\n📋 Login credentials:")
        print("  🔑 SuperAdmin: mysuperadmin@legalaid.com / mysuper123")
        print("  👤 Admin: admin@legalaid.com / admin123")
        print("  👤 Test Admin: testadmin@legalaid.com / testadmin123")
        print("  👤 User: user@legalaid.com / password123")
        print("  👤 Test User: testuser@legalaid.com / testuser123")
        
    except Exception as e:
        db.rollback()
        print(f" Error seeding users: {e}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed_users()

