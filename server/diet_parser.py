import pdfplumber
import os
import json
import google.generativeai as genai
from typing import List, Optional, Dict
from pydantic import BaseModel, Field

# --- MODELLI DATI (SCHEMA JSON) ---
# Identici a prima, servono a definire la struttura per Gemini
class Ingrediente(BaseModel):
    name: str = Field(description="Nome pulito dell'alimento (es. 'Pasta di semola'). Correggi errori OCR.")
    qty: str = Field(description="Quantità normalizzata (es. '70g', '1 tazza'). Correggi troncamenti (es '7' -> '70g' per pasta).")
    cad_code: Optional[str] = Field(default=None, description="Codice CAD numerico se presente.")
    is_group: bool = Field(default=False)
    ingredients: List['Ingrediente'] = Field(default_factory=list)

class Piatto(BaseModel):
    name: str = Field(description="Nome del piatto o raggruppamento (es. 'Colazione', 'Prima', 'Pasta al sugo').")
    qty: str = Field(default="N/A")
    cad_code: Optional[str] = Field(default=None)
    is_group: bool = Field(default=True)
    ingredients: List[Ingrediente] = Field(default_factory=list)

class OpzioneSostituzione(BaseModel):
    name: str
    qty: str
    ingredients: List[Ingrediente] = Field(default_factory=list)

class InfoSostituzione(BaseModel):
    info: str = Field(description="Descrizione testuale della ricetta o note di preparazione.")
    options: List[OpzioneSostituzione]

class PianoDieta(BaseModel):
    type: str = Field(default="complex")
    plan: Dict[str, Dict[str, List[Piatto]]] = Field(description="Mappa: Giorno -> Pasto (Pranzo/Cena) -> Lista Piatti")
    substitutions: Dict[str, InfoSostituzione] = Field(description="Mappa: Codice CAD -> Dettagli sostituzione")

# --- PARSER ---
class DietParser:
    def __init__(self):
        # Assicurati di settare GOOGLE_API_KEY
        api_key = os.getenv("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("Manca la variabile d'ambiente GOOGLE_API_KEY!")
        
        genai.configure(api_key=api_key)
        
        # Configurazione specifica per JSON output
        self.generation_config = {
            "temperature": 0.1, # Molto preciso
            "response_mime_type": "application/json",
            "response_schema": PianoDieta # Passiamo lo schema Pydantic direttamente!
        }
        
        # Usiamo Gemini 1.5 Flash (Gratuito e Veloce)
        self.model = genai.GenerativeModel(
            "gemini-1.5-flash",
            generation_config=self.generation_config
        )

    def extract_text_from_pdf(self, pdf_path: str) -> str:
        """Estrae tutto il testo grezzo dal PDF."""
        full_text = ""
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    full_text += text + "\n"
        return full_text

    def parse_complex_diet(self, pdf_path: str) -> PianoDieta:
        print(f"--- [GEMINI PARSER] Avvio analisi: {pdf_path} ---")
        
        raw_text = self.extract_text_from_pdf(pdf_path)
        if not raw_text:
            raise ValueError("Il PDF sembra vuoto o non leggibile.")

        system_prompt = """
        Sei un nutrizionista AI esperto in data cleaning. 
        Analizza il testo OCR di una dieta e convertilo in JSON.
        
        REGOLE CRITICHE DI PULIZIA:
        1. Unisci parole spezzate: "pis elli" -> "piselli", "m elanzane" -> "melanzane".
        2. Correggi quantità illogiche: Se leggi "Pasta gr 7", correggi in "gr 70" (porzione standard).
        3. Rimuovi intestazioni inutili (es. "Alimento Quantità CAD", "Elaborazione a cura di").
        4. Se un piatto ha un codice numerico (es. 30), usalo come chiave in 'substitutions'.
        5. Se mancano codici ma ci sono alternative nel testo, crea ID univoci (es. "SUB_AUTO_1").
        """

        try:
            # Inviamo la richiesta a Gemini
            response = self.model.generate_content([system_prompt, raw_text])
            
            # Parsing della risposta JSON
            json_response = json.loads(response.text)
            
            # Validazione finale con Pydantic
            dieta_parsed = PianoDieta(**json_response)
            
            return dieta_parsed

        except Exception as e:
            print(f"ERRORE API GOOGLE: {e}")
            raise e