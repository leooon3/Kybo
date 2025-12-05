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

@app.get("/")
def read_root():
    return {"status": "Server Attivo (Gemini Edition)! 🚀", "message": "Usa /upload-diet"}

@app.post("/upload-diet")
async def upload_diet(file: UploadFile = File(...)):
    try:
        print(f"📥 Ricevuto file dieta: {file.filename}")
        
        with open(DIET_PDF_PATH, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # 1. Inizializza Parser Gemini
        # NOTA: serve la variabile GOOGLE_API_KEY
        parser = DietParser() 
        
        # 2. Ottieni oggetto Pydantic
        dieta_model = parser.parse_complex_diet(DIET_PDF_PATH)
        
        # 3. Converti in JSON
        final_data = dieta_model.model_dump()
        
        # 4. Salva su disco
        with open(DIET_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
            
        print("✅ Dieta elaborata da Gemini e salvata.")
        return JSONResponse(content=final_data)

    except Exception as e:
        print(f"❌ Errore: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    # ... (CODICE IDENTICO A PRIMA PER LO SCONTRINO) ...
    # Copia la parte scan_receipt dallo snippet precedente se serve, 
    # ma non è cambiata rispetto alla tua versione.
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