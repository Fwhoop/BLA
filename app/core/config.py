from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "sqlite:///./fallback.db"
    jwt_secret: str = "change-me-in-production"
    port: int = 8000
    debug: bool = True

    mysql_root_password: str | None = None
    mysql_database: str | None = None
    mysql_user: str | None = None
    mysql_password: str | None = None

    hf_token: str | None = None

    class Config:
        env_file = ".env"

settings = Settings()
