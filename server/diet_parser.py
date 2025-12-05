import google.generativeai as genai
import typing_extensions as typing
import os

# Configura la tua API Key (scommenta e inserisci la tua chiave se non è già nell'ambiente)
# genai.configure(api_key=os.environ["GOOGLE_API_KEY"])

# --- DEFINIZIONE DELLA STRUTTURA DATI (Schema) ---
class Ingrediente(typing.TypedDict):
    nome: str
    quantita: str

class Piatto(typing.TypedDict):
    nome_piatto: str
    tipo: str  # "composto" o "singolo"
    quantita_totale: str # Solo se è singolo (es. "200 gr")
    ingredienti: list[Ingrediente] # Solo se è composto

class Pasto(typing.TypedDict):
    tipo_pasto: str # "Colazione", "Pranzo", "Cena", etc.
    elenco_piatti: list[Piatto]

class GiornoDieta(typing.TypedDict):
    giorno: str # "Lunedì", "Martedì", etc.
    pasti: list[Pasto]

# --- ISTRUZIONI DI SISTEMA AGGIORNATE (LA PARTE FONDAMENTALE) ---
system_instruction = """
Sei un assistente nutrizionista esperto in parsing di documenti dietetici.
Il tuo compito è estrarre il piano alimentare dal testo fornito e strutturarlo in JSON.

**REGOLE FONDAMENTALI DI PARSING (CRUCIALE):**

1.  **Analisi Riga per Riga:** Leggi attentamente ogni riga di alimento.
2.  **Rilevamento PIATTO COMPOSTO:**
    * Se una riga contiene il nome di un piatto ma **NON contiene alcuna quantità** (es. numeri seguiti da gr, g, ml, vasetti, cucchiaini), consideralo un "Titolo di Piatto Composto".
    * Gli alimenti nelle righe immediatamente successive sono i suoi **Ingredienti** SOLO SE iniziano con un pallino (•) o sono chiaramente indentati sotto il titolo.
3.  **Rilevamento ALIMENTO SINGOLO:**
    * Se una riga contiene un nome alimento E **contiene una quantità** (es. "Tonno 100 gr", "Pane 50 gr"), questo è un "Alimento Singolo".
    * **ECCEZIONE IMPORTANTE:** Se trovi un alimento con quantità (es. "Tonno 100 gr") subito dopo un "Piatto Composto" (es. "Pasta alle melanzane"), ma questo alimento **NON ha il pallino (•)** davanti, NON fa parte del piatto composto. È un secondo piatto separato.
4.  **Esempio Logico:**
    * Input:
        "Pasta alle melanzane" (Nessuna quantità -> TITOLO)
        "• Pasta 70 gr" (Pallino -> INGREDIENTE di Pasta alle melanzane)
        "• Melanzane 40 gr" (Pallino -> INGREDIENTE di Pasta alle melanzane)
        "Tonno 100 gr" (Ha quantità e NO pallino -> NUOVO PIATTO SINGOLO, staccato dalla pasta)

Restituisci solo il JSON strutturato secondo lo schema fornito.
"""

def estrai_dieta_con_gemini(contenuto_pdf_text):
    model = genai.GenerativeModel(
        model_name="gemini-1.5-flash",
        system_instruction=system_instruction,
        generation_config={
            "response_mime_type": "application/json",
            "response_schema": list[GiornoDieta]
        }
    )

    prompt = f"""
    Analizza il seguente testo estratto da una dieta e applica RIGOROSAMENTE le regole sui piatti composti vs alimenti singoli.
    
    TESTO DIETA:
    {contenuto_pdf_text}
    """

    response = model.generate_content(prompt)
    
    return response.text