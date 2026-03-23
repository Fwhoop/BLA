from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from .core.config import settings

def _fix_mysql_url(url: str) -> str:
    """Railway provides mysql:// but SQLAlchemy+PyMySQL needs mysql+pymysql://"""
    if url.startswith("mysql://"):
        return url.replace("mysql://", "mysql+pymysql://", 1)
    return url

_db_url = _fix_mysql_url(settings.database_url)

engine = create_engine(_db_url, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Base(DeclarativeBase):
    pass

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
