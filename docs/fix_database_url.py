"""
Helper script to fix database URL for MariaDB without password
"""
import os
from pathlib import Path

def fix_env_file():
    """Update .env file to use database URL without password"""
    env_path = Path(".env")
    
    if not env_path.exists():
        print("❌ .env file not found!")
        print("Creating a new .env file...")
        
        # Create default .env file
        env_content = """# Database Configuration
# MariaDB/MySQL Database URL (no password)
DATABASE_URL=mysql+pymysql://root@localhost:3306/barangay_legal_aid

# JWT Secret Key
JWT_SECRET=your-secret-key-change-this-in-production

# Server Configuration
PORT=8000
DEBUG=True
"""
        with open(env_path, 'w') as f:
            f.write(env_content)
        print("✅ Created .env file with no-password database URL")
        return
    
    # Read existing .env file
    with open(env_path, 'r') as f:
        lines = f.readlines()
    
    # Update DATABASE_URL
    updated = False
    new_lines = []
    for line in lines:
        if line.startswith('DATABASE_URL='):
            # Check if it has a password
            if '://root:' in line or '://root@' in line:
                # Update to no password format
                new_lines.append('DATABASE_URL=mysql+pymysql://root@localhost:3306/barangay_legal_aid\n')
                updated = True
                print("✅ Updated DATABASE_URL to use no password")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    
    # If DATABASE_URL wasn't found, add it
    if not updated:
        # Check if DATABASE_URL exists at all
        has_db_url = any('DATABASE_URL' in line for line in lines)
        if not has_db_url:
            new_lines.insert(0, 'DATABASE_URL=mysql+pymysql://root@localhost:3306/barangay_legal_aid\n')
            print("✅ Added DATABASE_URL with no password")
            updated = True
    
    if updated:
        # Write back to file
        with open(env_path, 'w') as f:
            f.writelines(new_lines)
        print("✅ .env file updated successfully!")
    else:
        print("✅ DATABASE_URL already configured correctly (no password)")
    
    print("\n📋 Current DATABASE_URL format:")
    print("   mysql+pymysql://root@localhost:3306/barangay_legal_aid")
    print("\n⚠️  Make sure:")
    print("   1. MariaDB is running")
    print("   2. Database 'barangay_legal_aid' exists")
    print("   3. User 'root' can connect without password")

if __name__ == "__main__":
    fix_env_file()



