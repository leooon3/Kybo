import os
import uuid
import logging
import aiofiles
import json
from typing import Optional

import firebase_admin
from firebase_admin import credentials, auth
from fastapi import FastAPI, UploadFile, File, HTTPException, Form, Header, Depends, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.concurrency import run_in_threadpool
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from app.services.diet_service import DietParser
from app.services.receipt_service import ReceiptScanner
from app.services.notification_service import NotificationService
from app.services.normalization import normalize_meal_name
from app.core.config import settings

# --- CONFIGURATION ---
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf", ".webp"}

# --- LOGGING ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mydiet_api")

# --- FIREBASE SETUP ---
if not firebase_admin._apps:
    try:
        # Prioritize Environment Variables for Security
        if os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred)
            logger.info("🔥 Firebase initialized via Env Vars")
        elif os.path.exists("serviceAccountKey.json"):
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred)
            logger.info("🔥 Firebase initialized via File")
        else:
            logger.warning("⚠️ No Firebase credentials found. Auth will fail.")
    except Exception as e:
        logger.error(f"❌ Critical Firebase Init Error: {e}")

# --- RATE LIMITER ---
limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# --- CORS ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

# Services
notification_service = NotificationService()
diet_parser = DietParser()

# --- UTILS ---
async def save_upload_file(file: UploadFile, filename: str) -> None:
    size = 0
    try:
        async with aiofiles.open(filename, 'wb') as out_file:
            while content := await file.read(1024 * 1024):
                size += len(content)
                if size > MAX_FILE_SIZE:
                    raise HTTPException(status_code=413, detail="File too large")
                await out_file.write(content)
    except Exception as e:
        if os.path.exists(filename):
            os.remove(filename)
        raise e

def validate_extension(filename: str) -> str:
    ext = os.path.splitext(filename)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Invalid file type")
    return ext

# --- AUTH ---
async def verify_token(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid auth header")
    
    token = authorization.split("Bearer ")[1]
    try:
        decoded_token = await run_in_threadpool(auth.verify_id_token, token)
        return decoded_token['uid'] 
    except Exception:
        logger.warning("Auth token verification failed")
        raise HTTPException(status_code=401, detail="Invalid token")

# --- ENDPOINTS ---

@app.post("/upload-diet")
@limiter.limit("5/minute")
async def upload_diet(
    request: Request,
    file: UploadFile = File(...),
    fcm_token: Optional[str] = Form(None),
    user_id: str = Depends(verify_token) 
):
    if not file.filename.lower().endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF allowed")

    temp_filename = f"{uuid.uuid4()}.pdf"
    
    try:
        await save_upload_file(file, temp_filename)
        
        # Parse safely
        raw_data = await run_in_threadpool(diet_parser.parse_complex_diet, temp_filename)
        
        # Convert data 
        final_data = _convert_to_app_format(raw_data)
        
        if fcm_token:
            await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
            
        return JSONResponse(content=final_data)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Diet Upload Error: {e}")
        raise HTTPException(status_code=500, detail="Processing failed")
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

@app.post("/scan-receipt")
@limiter.limit("10/minute")
async def scan_receipt(
    request: Request,
    file: UploadFile = File(...),
    allowed_foods: str = Form(...),
    user_id: str = Depends(verify_token) 
):
    ext = validate_extension(file.filename)
    temp_filename = f"{uuid.uuid4()}{ext}"
    
    try:
        try:
            food_list = json.loads(allowed_foods)
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="Invalid JSON format")

        await save_upload_file(file, temp_filename)
        
        current_scanner = ReceiptScanner(allowed_foods_list=food_list)
        found_items = await run_in_threadpool(current_scanner.scan_receipt, temp_filename)
        
        return JSONResponse(content=found_items)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Receipt Scan Error: {e}")
        raise HTTPException(status_code=500, detail="Scanning failed")
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

def _convert_to_app_format(gemini_output):
    if not gemini_output:
        return {"plan": {}, "substitutions": {}}

    app_plan = {}
    app_substitutions = {}

    raw_subs = gemini_output.get('tabella_sostituzioni', [])
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
                    "name": opt.get('nome', 'Unknown'),
                    "qty": opt.get('quantita', '')
                })
            
            if not options: 
                options.append({"name": titolo, "qty": ""})

            app_substitutions[cad_key] = {
                "name": titolo,
                "options": options
            }

    raw_plan = gemini_output.get('piano_settimanale', [])
    
    for giorno in raw_plan:
        day_name = giorno.get('giorno', 'Sconosciuto').strip().capitalize()
        # Normalize Day Names
        for eng, it in [("lun", "Lunedì"), ("mar", "Martedì"), ("mer", "Mercoledì"), 
                        ("gio", "Giovedì"), ("ven", "Venerdì"), ("sab", "Sabato"), ("dom", "Domenica")]:
            if eng in day_name.lower(): day_name = it

        app_plan[day_name] = {}

        for pasto in giorno.get('pasti', []):
            meal_name = normalize_meal_name(pasto.get('tipo_pasto', ''))
            
            items = []
            for piatto in pasto.get('elenco_piatti', []):
                dish_name = str(piatto.get('nome_piatto') or 'Piatto')
                final_cad = piatto.get('cad_code', 0)
                if final_cad == 0:
                    final_cad = cad_lookup_map.get(dish_name.lower(), 0)

                formatted_ingredients = []
                for ing in piatto.get('ingredienti', []):
                    formatted_ingredients.append({
                        "name": str(ing.get('nome') or ''),
                        "qty": str(ing.get('quantita') or '')
                    })

                items.append({
                    "name": dish_name,
                    "qty": str(piatto.get('quantita_totale') or ''),
                    "cad_code": final_cad,
                    "is_composed": piatto.get('tipo') == 'composto',
                    "ingredients": formatted_ingredients
                })
            
            if meal_name in app_plan[day_name]:
                app_plan[day_name][meal_name].extend(items)
            else:
                app_plan[day_name][meal_name] = items

    return {
        "plan": app_plan,
        "substitutions": app_substitutions
    }