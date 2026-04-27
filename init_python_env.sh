#!/bin/bash
set -e

echo "=== Construyendo plantilla del ecosistema Docker + Python ==="

# 1. Dependencias de Python
cat << 'EOF' > requirements.txt
fastapi
uvicorn
EOF

# 2. El Plano del Contenedor (Dockerfile)
cat << 'EOF' > Dockerfile
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# 3. El Orquestador (docker-compose.yml)
cat << 'EOF' > docker-compose.yml
services:
  python_core:
    build: .
    container_name: python_worker
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - .:/app
      - /mnt/pipeline_data:/app/data
    environment:
      - TZ=America/Mexico_City
EOF

# 4. El punto de entrada (main.py) con logs a color
cat << 'EOF' > main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
import os
from datetime import datetime

class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    WARNING = '\033[93m'
    RED = '\033[91m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def debug_print(color, level, message):
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"{Colors.BOLD}{color}[{timestamp}] [{level}]{Colors.RESET} {message}", flush=True)

DATA_DIR = "/app/data"

@asynccontextmanager
async def lifespan(app: FastAPI):
    debug_print(Colors.HEADER, "SISTEMA", "Iniciando motor de FastAPI...")
    debug_print(Colors.BLUE, "CONFIG", f"Verificando enlace de datos (gcsfuse) en: {DATA_DIR}")
    
    if os.path.exists(DATA_DIR):
        debug_print(Colors.GREEN, "OK", "Volumen detectado correctamente.")
        if os.access(DATA_DIR, os.W_OK):
            debug_print(Colors.GREEN, "OK", "Permisos de escritura confirmados.")
        else:
            debug_print(Colors.WARNING, "ALERTA", "Directorio es de solo lectura. Revisa gcsfuse.")
    else:
        debug_print(Colors.RED, "ERROR", f"No se encontró {DATA_DIR}. El bucket no está montado.")
    
    yield
    debug_print(Colors.HEADER, "SISTEMA", "Deteniendo servicios de forma segura...")

app = FastAPI(title="Servidor de Procesamiento", lifespan=lifespan)

@app.get("/")
def estado_servidor():
    debug_print(Colors.CYAN, "PETICIÓN", "Endpoint raíz (/) invocado.")
    
    archivos = []
    gcs_status = "Desconectado"
    
    try:
        if os.path.exists(DATA_DIR):
            gcs_status = "Activo"
            archivos = os.listdir(DATA_DIR)
            debug_print(Colors.BLUE, "OP", f"Lectura exitosa. {len(archivos)} archivos en bucket.")
        else:
            debug_print(Colors.RED, "OP", "Fallo: Directorio inexistente.")
    except Exception as e:
        debug_print(Colors.RED, "ERROR", f"Fallo en I/O: {str(e)}")

    return {
        "status": "Contenedor Python en línea",
        "bucket_gcs": gcs_status,
        "archivos_detectados": len(archivos)
    }
EOF

echo "=== ¡Archivos generados con éxito! ==="
echo "Puedes iniciar la pila con: docker compose up -d --build"
