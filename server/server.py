from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse, FileResponse
import shutil
import os
import json
# from difflib import get_close_matches # Opzionale, per ora proviamo senza per semplicità

from diet_parser import DietParser
from receipt_scanner import ReceiptScanner

app = FastAPI()

DIET_PDF_PATH = "temp_dieta.pdf"
RECEIPT_PATH = "temp_scontrino"
DIET_JSON_PATH = "dieta.json"

def normalize_meal_name(raw_name):
    """
    Normalizza i nomi dei pasti del PDF per farli combaciare con l'App.
    """
    name = raw_name.lower().strip()
    
    # Mappatura specifica per il tuo PDF
    if "prima colazione" in name: return "Colazione"
    if "seconda colazione" in name: return "Seconda Colazione" # O "Spuntino Mattina" se l'app usa quello
    if "spuntino mattina" in name: return "Seconda Colazione"
    if "pranzo" in name: return "Pranzo"
    if "merenda" in name: return "Merenda"
    if "cena" in name: return "Cena"
    if "spuntino serale" in name: return "Spuntino Serale"
    
    return raw_name.title() # Default (es. "Nell'arco della giornata")

def convert_to_app_format(gemini_output):
    app_plan = {}
    app_substitutions = {}

    # 1. ELABORAZIONE SOSTITUZIONI
    raw_subs = gemini_output.get('tabella_sostituzioni', [])
    
    # Mappa di supporto per correggere eventuali CAD mancanti (Backfill)
    cad_lookup_map = {} 

    for group in raw_subs:
        cad_code = group.get('cad_code', 0)
        titolo = group.get('titolo', "").strip()
        
        if cad_code > 0:
            cad_key = str(cad_code)
            cad_lookup_map[titolo.lower()] = cad_code
            
            options = []
            for opt in group.get('opzioni', []):
                options.append({
                    "name": opt['nome'],
                    "qty": opt['quantita']
                })
            
            if not options: # Fallback se la lista è vuota
                options.append({"name": titolo, "qty": ""})

            app_substitutions[cad_key] = {
                "name": titolo,
                "options": options
            }

    # 2. ELABORAZIONE PIANO SETTIMANALE
    raw_plan = gemini_output.get('piano_settimanale', [])
    
    for giorno in raw_plan:
        # Normalizzazione nome giorno
        day_name = giorno.get('giorno', 'Sconosciuto').strip().capitalize()
        if "lun" in day_name.lower(): day_name = "Lunedì"
        elif "mar" in day_name.lower(): day_name = "Martedì"
        elif "mer" in day_name.lower(): day_name = "Mercoledì"
        elif "gio" in day_name.lower(): day_name = "Giovedì"
        elif "ven" in day_name.lower(): day_name = "Venerdì"
        elif "sab" in day_name.lower(): day_name = "Sabato"
        elif "dom" in day_name.lower(): day_name = "Domenica"

        app_plan[day_name] = {}

        for pasto in giorno.get('pasti', []):
            # QUI APPLICHIAMO LA CORREZIONE DEL NOME PASTO
            meal_name = normalize_meal_name(pasto.get('tipo_pasto', ''))
            
            items = []
            for piatto in pasto.get('elenco_piatti', []):
                original_cad = piatto.get('cad_code', 0)
                dish_name = piatto['nome_piatto']
                
                # TENTATIVO DI RECUPERO CAD (Se Gemini l'ha perso ma esiste nelle sostituzioni)
                final_cad = original_cad
                if final_cad == 0:
                    final_cad = cad_lookup_map.get(dish_name.lower(), 0)

                # Formattazione per l'App
                if piatto.get('tipo') == 'composto':
                    items.append({
                        "name": dish_name,
                        "qty": "N/A", # Trigger per raggruppamento App
                        "cad_code": final_cad
                    })
                    for ing in piatto.get('ingredienti', []):
                        items.append({
                            "name": ing['nome'],
                            "qty": ing['quantita'],
                            "is_ingredient": True
                        })
                else:
                    items.append({
                        "name": dish_name,
                        "qty": piatto.get('quantita_totale', ''),
                        "cad_code": final_cad
                    })
            
            # Se il pasto esiste già (es. due "spuntini" che diventano entrambi "Merenda"), li uniamo
            if meal_name in app_plan[day_name]:
                app_plan[day_name][meal_name].extend(items)
            else:
                app_plan[day_name][meal_name] = items

    return {
        "plan": app_plan,
        "substitutions": app_substitutions
    }

@app.get("/")
def read_root():
    return {"status": "Server Attivo", "actions": ["/upload-diet", "/debug/json"]}

@app.get("/debug/json")
def get_debug_json():
    if os.path.exists(DIET_JSON_PATH):
        return FileResponse(DIET_JSON_PATH, media_type='application/json', filename="dieta_debug.json")
    return {"error": "Nessun file presente"}

@app.post("/upload-diet")
async def upload_diet(file: UploadFile = File(...)):
    try:
        print(f"📥 Ricevuto PDF: {file.filename}")
        with open(DIET_PDF_PATH, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        parser = DietParser()
        # Estrazione
        raw_data = parser.parse_complex_diet(DIET_PDF_PATH)
        
        # Conversione e Correzione
        final_data = convert_to_app_format(raw_data)
        
        with open(DIET_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
            
        return JSONResponse(content=final_data)

    except Exception as e:
        print(f"❌ Errore: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    try:
        if not os.path.exists(DIET_JSON_PATH):
            raise HTTPException(status_code=400, detail="Carica prima la dieta!")
        ext = os.path.splitext(file.filename)[1]
        temp_filename = f"{RECEIPT_PATH}{ext}"
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        scanner = ReceiptScanner(DIET_JSON_PATH)
        found_items = scanner.scan_receipt(temp_filename)
        return JSONResponse(content=found_items)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)