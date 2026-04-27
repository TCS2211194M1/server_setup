#!/bin/bash
set -e

echo "=== Construyendo plantilla del ecosistema Docker + Python ==="

# 1. Dependencias de Python (Ajustado para API web y datos)
cat << 'EOF' > requirements.txt
fastapi
uvicorn
numpy
EOF

# 2. El Plano del Contenedor (Dockerfile)
# Usamos la versión 'slim' para mantener la imagen ligera pero funcional
cat << 'EOF' > Dockerfile
FROM python:3.11-slim

# Evitar que Python genere archivos .pyc y forzar salida en consola
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Instalar dependencias del sistema operativo que requiera tu código
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Instalar librerías de Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el resto del código
COPY . .

# Exponer el puerto para la web/API
EXPOSE 8000

# Levantar el servidor web de FastAPI
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
      # Sincronización en tiempo real de tu código fuente
      - .:/app
      # TU REGLA DE ORO: El enlace al Bucket de GCP
      - /mnt/pipeline_data:/app/data
    environment:
      - TZ=America/Mexico_City
EOF

# 4. El punto de entrada (main.py)
cat << 'EOF' > main.py
from fastapi import FastAPI
import os

app = FastAPI(title="Servidor de Procesamiento")

@app.get("/")
def estado_servidor():
    data_dir = "/app/data"
    gcs_status = "Activo" if os.path.exists(data_dir) else "Desconectado"
    
    return {
        "status": "🚀 Contenedor Python en línea",
        "bucket_gcs": gcs_status,
        "mensaje": "Aislamiento exitoso. SO base intacto."
    }
EOF

echo "=== ¡Archivos generados con éxito! ==="
