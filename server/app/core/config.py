import os
import json
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Loads from .env automatically
    GOOGLE_API_KEY: str = ""
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    
    # [FIX] Allow ALL origins (*) to fix "Failed to fetch" / CORS errors in Flutter Web
    ALLOWED_ORIGINS: list[str] = ["*"]

    # Paths
    DIET_PDF_PATH: str = "temp_dieta.pdf"
    RECEIPT_PATH_PREFIX: str = "temp_scontrino"
    DIET_JSON_PATH: str = "dieta.json"

    # Keywords
    MEAL_MAPPING: dict = {
        "prima colazione": "Colazione",
        "seconda colazione": "Seconda Colazione",
        "spuntino mattina": "Seconda Colazione",
        "pranzo": "Pranzo",
        "merenda": "Merenda",
        "cena": "Cena",
        "spuntino serale": "Spuntino Serale"
    }

    class Config:
        env_file = ".env"

settings = Settings()