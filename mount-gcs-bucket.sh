#!/bin/bash
set -euo pipefail

### ===== CONFIGURACIÓN =====
BUCKET_NAME="${1:-}"
MOUNT_POINT="/mnt/pipeline_data"
KEY_FILE="/etc/gcp/service-account.json"
GCSFUSE_BIN="$(command -v gcsfuse || true)"

### ===== LOGGING =====
log() { echo -e "\e[32m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

### ===== VALIDACIONES =====

[ -z "$BUCKET_NAME" ] && error "Debes proporcionar el nombre del bucket como argumento"

[ -z "$GCSFUSE_BIN" ] && error "gcsfuse no está instalado"

[ ! -f "$KEY_FILE" ] && error "No se encontró el archivo de credenciales en $KEY_FILE"

if ! command -v fusermount >/dev/null; then
    error "FUSE no está disponible en el sistema"
fi

### ===== PREPARACIÓN =====

log "Preparando punto de montaje..."

sudo mkdir -p "$MOUNT_POINT"
sudo chown "$USER:$USER" "$MOUNT_POINT"

### ===== DESMONTAR SI YA EXISTE =====

if mountpoint -q "$MOUNT_POINT"; then
    warn "El punto ya está montado. Intentando desmontar..."
    fusermount -u "$MOUNT_POINT" || error "No se pudo desmontar"
fi

### ===== MONTAJE =====

log "Montando bucket '$BUCKET_NAME' en $MOUNT_POINT..."

gcsfuse \
    --key-file "$KEY_FILE" \
    --implicit-dirs \
    --stat-cache-ttl 1m \
    --type-cache-ttl 1m \
    "$BUCKET_NAME" \
    "$MOUNT_POINT"

### ===== VERIFICACIÓN =====

if mountpoint -q "$MOUNT_POINT"; then
    log "Montaje exitoso"
else
    error "El montaje falló"
fi

### ===== OPCIONAL: PERSISTENCIA =====

read -p "¿Deseas hacerlo persistente (fstab)? [y/N]: " persist

if [[ "$persist" =~ ^[Yy]$ ]]; then
    log "Configurando montaje persistente..."

    FSTAB_LINE="$BUCKET_NAME $MOUNT_POINT gcsfuse rw,_netdev,allow_other,--key-file=$KEY_FILE 0 0"

    if ! grep -q "$BUCKET_NAME $MOUNT_POINT" /etc/fstab; then
        echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
        log "Entrada agregada a /etc/fstab"
    else
        warn "Ya existe una entrada en fstab"
    fi

    sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

    log "Persistencia configurada"
fi

log "Proceso completado ✅"
