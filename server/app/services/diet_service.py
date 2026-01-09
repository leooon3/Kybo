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

# --- DATA SCHEMAS (Your Original TypedDicts) ---
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
            print("❌ CRITICAL ERROR: GOOGLE_API_KEY not found in settings!")
            self.client = None
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            self.client = genai.Client(api_key=clean_key)

        # [DEFAULT SYSTEM INSTRUCTION]
        self.system_instruction = """
You are an expert AI Nutritionist and Data Analyst capable of understanding any language (English, Spanish, French, German, Italian, etc.).

YOUR TASK:
Extract the weekly diet plan from the provided document.

CRITICAL RULES FOR MULTI-LANGUAGE SUPPORT:
1. **Detect Language**: Read the document in its original language.
2. **Translate Structure (Required)**: 
   - You MUST translate the **Day of the Week** into Italian (e.g., "Monday" -> "Lunedì", "Domingo" -> "Domenica") for the `giorno` field.
   - You MUST translate the **Meal Category** into Italian (e.g., "Breakfast" -> "Colazione", "Lunch" -> "Pranzo", "Snack" -> "Spuntino", "Dinner" -> "Cena") for the `tipo_pasto` field.
3. **Preserve Content**: 
   - Keep the **Dish Names**, **Ingredients**, and **Quantities** in the **ORIGINAL LANGUAGE** of the document. Do not translate the food itself.

SIMPLIFIED SCHEMA RULES:
1. **Weekly Plan Only**: Extract every meal for every day found.
2. **No Substitutions**: This diet type implies no alternatives. You MUST return an empty list `[]` for the field `tabella_sostituzioni`.
3. **No CAD Codes**: Set `cad_code` to 0 for all items.

OUTPUT FORMAT (Strict JSON):
{
  "piano_settimanale": [
    {
      "giorno": "Lunedì", 
      "pasti": [
        {
          "tipo_pasto": "Colazione",
          "elenco_piatti": [
             { 
               "nome_piatto": "Oatmeal with berries", 
               "quantita_totale": "50g", 
               "cad_code": 0, 
               "tipo": "semplice", 
               "ingredienti": [] 
             }
          ]
        }
      ]
    }
  ],
  "tabella_sostituzioni": []
}"""

    def _extract_text_from_pdf(self, pdf_path: str) -> str:
        # [PRESERVED] Your Memory Optimization using StringIO
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
        # [PRESERVED] Your Robust JSON extraction
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

    # [UPDATED] Added optional custom_instructions parameter
    def parse_complex_diet(self, file_path: str, custom_instructions: str = None):
        if not self.client:
            raise ValueError("Client Gemini non inizializzato (manca API KEY).")

        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("PDF vuoto o illeggibile.")

        model_name = settings.GEMINI_MODEL
        
        # [NEW LOGIC] Determine which prompt to use
        # If custom_instructions exists, use it. Otherwise, use self.system_instruction.
        final_instruction = custom_instructions if custom_instructions else self.system_instruction
        
        try:
            print(f"🤖 Analisi Gemini ({model_name})... Using Custom Prompt: {bool(custom_instructions)}")
            
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
                    system_instruction=final_instruction, # <--- Uses the dynamic prompt
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