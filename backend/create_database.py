"""
Script to create the database if it doesn't exist
"""
import pymysql
from app.core.config import settings

def create_database():
    """Create the database if it doesn't exist"""
    try:
        # Parse database URL to get connection details
        db_url = settings.database_url
        # Format: mysql+pymysql://root@localhost:3306/barangay_legal_aid
        
        # Extract parts
        db_url = db_url.replace("mysql+pymysql://", "")
        
        if "@" in db_url:
            auth_part, rest = db_url.split("@", 1)
            if ":" in auth_part:
                db_user, db_password = auth_part.split(":", 1)
            else:
                db_user = auth_part
                db_password = ""
        else:
            db_user = "root"
            db_password = ""
        
        if "/" in rest:
            host_part, db_name = rest.split("/", 1)
            if ":" in host_part:
                db_host, db_port = host_part.split(":", 1)
            else:
                db_host = host_part
                db_port = "3306"
        else:
            db_host = "localhost"
            db_port = "3306"
            db_name = "barangay_legal_aid"
        
        print(f"🔌 Connecting to MariaDB at {db_host}:{db_port} as {db_user}...")
        
        # Connect without specifying database
        if db_password:
            conn = pymysql.connect(
                host=db_host,
                port=int(db_port),
                user=db_user,
                password=db_password
            )
        else:
            conn = pymysql.connect(
                host=db_host,
                port=int(db_port),
                user=db_user
            )
        
        cursor = conn.cursor()
        
        # Check if database exists
        cursor.execute("SHOW DATABASES LIKE %s", (db_name,))
        exists = cursor.fetchone()
        
        if exists:
            print(f"✅ Database '{db_name}' already exists")
        else:
            # Create database
            print(f"📊 Creating database '{db_name}'...")
            cursor.execute(f"CREATE DATABASE IF NOT EXISTS {db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            print(f"✅ Database '{db_name}' created successfully!")
        
        cursor.close()
        conn.close()
        
        print("\n✅ Database setup complete!")
        print(f"   Database: {db_name}")
        print(f"   Host: {db_host}:{db_port}")
        print(f"   User: {db_user}")
        
    except Exception as e:
        print(f"❌ Error creating database: {e}")
        print("\n💡 Make sure:")
        print("   1. MariaDB is running")
        print("   2. You can connect with: mysql -u root")
        raise

if __name__ == "__main__":
    create_database()


