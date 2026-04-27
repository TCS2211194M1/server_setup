#!/bin/bash
set -e

# --- Configuración de Colores para el Script Bash ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Iniciando Orquestador de Ecosistema (Regla de Oro) ===${NC}"

# 1. Verificación e Instalación de Docker (Host)
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}[!] Docker no detectado. Iniciando instalación en el host...${NC}"
    sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Usamos el repo de 'noble' por estabilidad en Ubuntu 25.10
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo usermod -aG docker $USER
    echo -e "${GREEN}[OK] Motor de Docker instalado.${NC}"
else
    echo -e "${GREEN}[OK] Docker ya está presente en el sistema operativo base.${NC}"
fi

# 2. Generación de Archivos del Entorno (Aislamiento)
echo -e "${BLUE}=== Generando archivos de configuración para Python ===${NC}"

# requirements.txt
cat << 'EOF' > requirements.txt
fastapi
uvicorn
numpy
EOF

# Dockerfile
cat << 'EOF' > Dockerfile
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# docker-compose.yml
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

# main.py (Con debugging de colores profesional)
cat << 'EOF' > main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
import os
from datetime import datetime

class C:
    HEADER, BLUE, GREEN, WARN, RED, RESET = '\033[95m', '\033[94m', '\033[92m', '\033[93m', '\033[91m', '\033[0m'

def d_print(color, level, msg):
    print(f"{color}[{datetime.now().strftime('%H:%M:%S')}] [{level}]{C.RESET} {msg}", flush=True)

@asynccontextmanager
async def lifespan(app: FastAPI):
    d_print(C.HEADER, "SISTEMA", "Iniciando motor de FastAPI...")
    path = "/app/data"
    if os.path.exists(path):
        d_print(C.GREEN, "OK", f"GCS Bucket vinculado en {path}")
    else:
        d_print(C.RED, "ERROR", "Falta el punto de montaje /app/data")
    yield
    d_print(C.HEADER, "SISTEMA", "Apagado seguro.")

app = FastAPI(lifespan=lifespan)

@app.get("/")
def home():
    d_print(C.BLUE, "INFO", "Petición HTTP recibida.")
    return {"status": "Online", "mode": "Containerized"}
EOF

echo -e "${GREEN}=== ¡Entorno listo! ===${NC}"
echo -e "${YELLOW}Ejecutando orquestación final...${NC}"

# 3. Lanzar la pila
docker compose up -d --build

echo -e "${GREEN}Despliegue completado.${NC}"
echo -e "Monitorea los logs con: ${BLUE}docker compose logs -f${NC}"
