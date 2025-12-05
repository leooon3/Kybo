from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import shutil
import os
import json

# Import moduli locali
from diet_parser import DietParser
from receipt_scanner import ReceiptScanner

app = FastAPI()

# Percorsi file
DIET_PDF_PATH = "temp_dieta.pdf"
RECEIPT_PATH = "temp_scontrino"
DIET_JSON_PATH = "dieta.json"

def convert_to_app_format(gemini_data):
    """
    Traduce l'output di Gemini (Lista di Giorni) nel formato Mappa 
    che l'App Flutter si aspetta:
    Input: [ {"giorno": "Lunedì", "pasti": [...]}, ... ]
    Output: { "Lunedì": { "Pranzo": [ {"name": "Pasta", "qty": "100g"}, ... ] }, ... }
    """
    app_data = {}
    
    # Se gemini_data è vuoto o None, restituiamo dict vuoto
    if not gemini_data:
        return {}

    for giorno in gemini_data:
        # Prende il nome del giorno (es. "Lunedì")
        day_name = giorno.get('giorno', 'Sconosciuto').strip()
        
        # Inizializza la mappa per quel giorno
        app_data[day_name] = {}
        
        # Itera sui pasti (Colazione, Pranzo, etc.)
        for pasto in giorno.get('pasti', []):
            meal_name = pasto.get('tipo_pasto', 'Altro')
            items = []
            
            # Itera sui piatti di quel pasto
            for piatto in pasto.get('elenco_piatti', []):
                
                # Caso 1: Piatto Composto (es. Pasta al sugo)
                if piatto.get('tipo') == 'composto':
                    # 1. Aggiunge il TITOLO del piatto (senza quantità)
                    items.append({
                        "name": piatto['nome_piatto'],
                        "qty": "" 
                    })
                    # 2. Aggiunge gli INGREDIENTI sotto come voci elenco puntato
                    for ing in piatto.get('ingredienti', []):
                        items.append({
                            "name": f"• {ing['nome']}",
                            "qty": ing['quantita']
                        })
                
                # Caso 2: Alimento Singolo (es. Mela)
                else:
                    items.append({
                        "name": piatto['nome_piatto'],
                        "qty": piatto.get('quantita_totale', '')
                    })
            
            # Assegna la lista di cibi a quel pasto
            app_data[day_name][meal_name] = items
            
    return app_data

@app.get("/")
def read_root():
    return {"status": "Server Attivo e Pronto per l'App! 🚀", "message": "Usa /upload-diet"}

@app.post("/upload-diet")
async def upload_diet(file: UploadFile = File(...)):
    try:
        print(f"📥 Ricevuto file dieta: {file.filename}")
        
        with open(DIET_PDF_PATH, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # 1. Inizializza Parser
        parser = DietParser() 
        
        # 2. Ottieni i dati grezzi da Gemini (che è una LISTA)
        raw_data = parser.parse_complex_diet(DIET_PDF_PATH)
        
        # 3. Converti nel formato Mappa per l'App
        final_data = convert_to_app_format(raw_data)
        
        # 4. Salva su disco (per debug)
        with open(DIET_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
            
        print("✅ Dieta convertita correttamente nel formato App.")
        
        # 5. Restituisci l'oggetto JSON con la chiave "plan"
        # Questo risolve l'errore List vs Map
        return JSONResponse(content={
            "plan": final_data,
            "substitutions": {} 
        })

    except Exception as e:
        print(f"❌ Errore durante l'elaborazione: {e}")
        # Stampiamo l'errore nei log per capire meglio
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    try:
        print(f"📥 Ricevuto scontrino: {file.filename}")
        if not os.path.exists(DIET_JSON_PATH):
            raise HTTPException(status_code=400, detail="Carica prima la dieta!")

        ext = os.path.splitext(file.filename)[1]
        temp_filename = f"{RECEIPT_PATH}{ext}"
        
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        scanner = ReceiptScanner(DIET_JSON_PATH)
        found_items = scanner.scan_receipt(temp_filename)
        
        print(f"✅ Scontrino analizzato: trovati {len(found_items)} prodotti.")
        return JSONResponse(content=found_items)

    except Exception as e:
        print(f"❌ Errore: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    print("🌐 Avvio server su http://0.0.0.0:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)