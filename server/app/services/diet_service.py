import json
import re
import io
import pdfplumber
import os
from google import genai
from google.genai import types
from app.core.config import settings
from app.models.schemas import (
    DietResponse, 
    Dish, 
    Ingredient, 
    SubstitutionGroup, 
    SubstitutionOption
)
import typing_extensions as typing

# --- SCHEMI DATI ---
class Ingrediente(typing.TypedDict):
    nome: str
    quantita: str

class Piatto(typing.TypedDict):
    nome_piatto: str
    tipo: str
    cad_code: int
    quantita_totale: str
    ingredienti: list[Ingrediente]

class Pasto(typing.TypedDict):
    tipo_pasto: str
    elenco_piatti: list[Piatto]

class GiornoDieta(typing.TypedDict):
    giorno: str 
    pasti: list[Pasto]

class OpzioneSostituzione(typing.TypedDict):
    nome: str
    quantita: str

class GruppoSostituzione(typing.TypedDict):
    cad_code: int
    titolo: str
    opzioni: list[OpzioneSostituzione]

class OutputDietaCompleto(typing.TypedDict):
    piano_settimanale: list[GiornoDieta]
    tabella_sostituzioni: list[GruppoSostituzione]

class DietParser:
    def __init__(self):
        api_key = settings.GOOGLE_API_KEY
        if not api_key:
            print("❌ ERRORE CRITICO: GOOGLE_API_KEY non trovata nelle impostazioni!")
            self.client = None
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            self.client = genai.Client(api_key=clean_key)

        # [FIX] Improved System Instruction: Semantic extraction over visual layout
        self.system_instruction = """
        Sei un nutrizionista esperto e un analista dati. Il tuo compito è convertire un documento PDF di una dieta in un JSON strutturato.
        
        ISTRUZIONI DI ESTRAZIONE:
        
        1. **PIANO SETTIMANALE**:
           - Estrai ogni pasto per ogni giorno (Colazione, Spuntino, Pranzo, Merenda, Cena).
           - **Identificazione CAD**: Il "Codice CAD" è un numero intero associato univocamente a un piatto. 
             - Cerca numeri isolati accanto al nome del piatto o nella colonna finale.
             - Esempio: "Pasta al pomodoro ... 30" -> cad_code: 30.
             - Se non trovi un numero esplicito, metti 0.

        2. **TABELLA SOSTITUZIONI (CAD)**:
           - Cerca sezioni intitolate "Elenco numeri di CAD" o "Sostituzioni".
           - Ogni gruppo ha un ID (es. 16, 19) e un Titolo (es. "PASTA").
           - Estrai l'elenco delle opzioni (cibo alternativo + quantità) per quel gruppo.

        OUTPUT:
        Restituisci SOLAMENTE un JSON valido che rispetti lo schema fornito. Nessun markdown, nessun commento.
        """

    def _extract_text_from_pdf(self, pdf_path: str) -> str:
        # [FIX] Memory Optimization using StringIO
        text_buffer = io.StringIO()
        try:
            file_size = os.path.getsize(pdf_path)
            if file_size > 10 * 1024 * 1024: 
                raise ValueError("PDF troppo grande per l'elaborazione (Max 10MB).")

            with pdfplumber.open(pdf_path) as pdf:
                if len(pdf.pages) > 50:
                    raise ValueError("Il PDF ha troppe pagine (Max 50).")
                
                for page in pdf.pages:
                    extracted = page.extract_text(layout=True) 
                    if extracted:
                        text_buffer.write(extracted)
                        text_buffer.write("\n")
            
            return text_buffer.getvalue()
        except Exception as e:
            print(f"❌ Errore lettura PDF: {e}")
            raise e
        finally:
            text_buffer.close()

    def _extract_json_from_text(self, text: str):
        # [FIX] Robust JSON extraction from unstructured LLM response
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Try to find JSON block delimiters
        match = re.search(r'\{.*\}', text, re.DOTALL)
        if match:
            clean_text = match.group(0)
            try:
                return json.loads(clean_text)
            except json.JSONDecodeError:
                pass
        
        raise ValueError("Impossibile estrarre JSON valido dalla risposta Gemini.")

    def parse_complex_diet(self, file_path: str):
        if not self.client:
            raise ValueError("Client Gemini non inizializzato (manca API KEY).")

        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("PDF vuoto o illeggibile.")

        model_name = settings.GEMINI_MODEL
        
        try:
            print(f"🤖 Analisi Gemini ({model_name})...")
            
            prompt = f"""
            Analizza il seguente testo ed estrai i dati della dieta e le sostituzioni CAD.
            
            <source_document>
            {diet_text}
            </source_document>
            """

            response = self.client.models.generate_content(
                model=model_name,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=self.system_instruction,
                    response_mime_type="application/json",
                    response_schema=OutputDietaCompleto
                )
            )
            
            # Prioritize structured parsing provided by SDK
            if hasattr(response, 'parsed') and response.parsed:
                return response.parsed
            
            # Fallback to text parsing
            if hasattr(response, 'text') and response.text:
                return self._extract_json_from_text(response.text)
            
            raise ValueError("Risposta vuota da Gemini")

        except Exception as e:
            print(f"⚠️ Errore con Gemini: {e}")
            raise e