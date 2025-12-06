NutriScan
Sistema digitale per la gestione della dieta e della dispensa. Converte i piani nutrizionali PDF in programmi interattivi e automatizza la lista della spesa tramite la scansione degli scontrini.

Funzionalità
Parsing Dieta PDF: Estrae pasti, quantità e giorni da file PDF non strutturati utilizzando l'IA di Gemini.

Scanner Scontrini: Aggiunge prodotti al "Frigo Virtuale" tramite OCR e corrispondenza fuzzy delle stringhe (fuzzy matching).

Lista Spesa Intelligente: Calcola gli articoli necessari sottraendo l'inventario della dispensa dal piano dietetico.

Sostituzione Pasti: Suggerisce alternative basate sui codici di composizione degli alimenti (CAD).

Modalità Relax: Attiva o disattiva la visibilità delle grammature specifiche per ridurre lo stress.

Multipiattaforma: Sviluppato con Flutter (Mobile/Web/Desktop) e Python (FastAPI).

Stack Tecnologico
Frontend: Flutter, Provider (Gestione dello Stato), HTTP.

Backend: Python, FastAPI, Uvicorn.

AI/OCR: Google Gemini (Parsing PDF), Tesseract OCR (Scontrini), TheFuzz (Matching stringhe).

Installazione
1. Backend (Server)
Naviga nella cartella server/.

Requisiti:

Python 3.9+

Tesseract OCR installato sul sistema host.

Setup:

Bash

cd server
pip install -r requirements.txt
Configurazione: Crea un file .env nella cartella server/:

Ini, TOML

GOOGLE_API_KEY=la_tua_chiave_api_gemini
Esecuzione:

Bash

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
2. Frontend (App)
Naviga nella cartella mydiet/.

Setup:

Bash

cd mydiet
flutter pub get
Configurazione: Assicurati che lib/core/env.dart (o il file .env lato client) punti all'indirizzo IP corretto del backend (default: http://10.0.2.2:8000 per l'emulatore Android o il tuo IP locale).

Esecuzione:

Bash

flutter run
Utilizzo
Carica Dieta: Apri il menu laterale, seleziona "Carica Dieta PDF". Carica il file fornito dal nutrizionista.

Riempi la Dispensa: Vai su "Dispensa". Aggiungi articoli manualmente o tocca l'icona Fotocamera per scansionare uno scontrino (Immagine o PDF).

Genera Lista: Vai su "Lista". Seleziona i giorni o i pasti desiderati. Il sistema controlla la dispensa ed elenca solo ciò che manca.

Gestisci Pasti: Tocca le frecce per sostituire i pasti con alternative valide. Tieni premuto su un piatto per modificarne i dettagli. Tocca la casella di controllo per segnarlo come consumato.

Struttura del Progetto
mydiet/: Codice dell'applicazione Flutter.

server/: Backend Python FastAPI.

app/services/diet_service.py: Interazione con LLM per il parsing del PDF.

app/services/receipt_service.py: Logica OCR e algoritmo di matching fuzzy.
