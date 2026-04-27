#!/bin/bash
# Evitamos -e global para poder capturar y manejar errores específicos con elegancia
set -uo pipefail

### ===== COLORES Y LOGGING =====
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}>>> $1${NC}"; }

### ===== 1. INTERACTIVIDAD Y CONFIGURACIÓN =====
step "Configuración de Variables"

# Si no se pasa como argumento, lo preguntamos
BUCKET_NAME="${1:-}"
if [ -z "$BUCKET_NAME" ]; then
    read -p "Introduce el nombre del bucket de GCP: " BUCKET_NAME
fi

[ -z "$BUCKET_NAME" ] && error "El nombre del bucket es obligatorio."

# Preguntamos por rutas con valores por defecto
read -p "Punto de montaje [/mnt/pipeline_data]: " INPUT_MOUNT
MOUNT_POINT=${INPUT_MOUNT:-/mnt/pipeline_data}

read -p "Ruta del Service Account JSON [/etc/gcp/service-account.json]: " INPUT_KEY
KEY_FILE=${INPUT_KEY:-/etc/gcp/service-account.json}

LOG_FILE="/tmp/gcsfuse_${BUCKET_NAME}.log"

### ===== 2. VALIDACIONES DE SISTEMA =====
step "Verificaciones pre-vuelo"

command -v gcsfuse >/dev/null 2>&1 || error "gcsfuse no está instalado. Ejecuta: sudo apt install gcsfuse"
command -v fusermount >/dev/null 2>&1 || error "FUSE no está instalado."
[ ! -f "$KEY_FILE" ] && error "No se encontró el archivo de credenciales en $KEY_FILE"

# Verificamos si tenemos permisos de sudo activos
sudo -v || error "Se requieren privilegios de sudo para configurar FUSE y el montaje."

### ===== 3. PREPARACIÓN FUSE Y DOCKER =====
step "Configurando FUSE para acceso global (Docker Compatible)"

# Para que Docker o cualquier otro usuario pueda leer el bucket, FUSE debe permitirlo
if ! grep -q "^user_allow_other" /etc/fuse.conf; then
    warn "Habilitando 'user_allow_other' en /etc/fuse.conf..."
    sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf || \
    echo "user_allow_other" | sudo tee -a /etc/fuse.conf > /dev/null
fi

log "Preparando directorio $MOUNT_POINT..."
sudo mkdir -p "$MOUNT_POINT"
sudo chown "$USER:$USER" "$MOUNT_POINT"

### ===== 4. LIMPIEZA DE MONTAJES ZOMBIE =====
step "Comprobando estado del montaje"

if mountpoint -q "$MOUNT_POINT" || grep -qs "$MOUNT_POINT" /proc/mounts; then
    warn "Detectado montaje previo o estancado. Forzando desmontaje..."
    # -z hace un lazy unmount: lo desconecta de la jerarquía inmediatamente aunque esté ocupado
    sudo fusermount -uz "$MOUNT_POINT" 2>/dev/null || sudo umount -l "$MOUNT_POINT" 2>/dev/null
    sleep 2
fi

### ===== 5. EJECUCIÓN DEL MONTAJE =====
step "Iniciando GCSFuse"

log "Escribiendo logs de depuración en: $LOG_FILE"
# Vaciamos el log anterior
> "$LOG_FILE"

# Ejecutamos gcsfuse con parámetros actualizados para v3.9.0+
gcsfuse \
    --key-file "$KEY_FILE" \
    --implicit-dirs \
    --metadata-cache-ttl-secs 60 \
    -o allow_other \
    --uid 1000 \
    --gid 1000 \
    --log-file "$LOG_FILE" \
    --log-format "text" \
    --log-severity TRACE \
    "$BUCKET_NAME" \
    "$MOUNT_POINT"

### ===== 6. VERIFICACIÓN ROBUSTA =====
step "Auditoría de Montaje"

sleep 2 # Le damos tiempo a FUSE para estabilizarse

if mountpoint -q "$MOUNT_POINT"; then
    log "¡Montaje de '$BUCKET_NAME' en $MOUNT_POINT exitoso!"
    
    # Prueba de escritura rápida
    if touch "$MOUNT_POINT/.gcsfuse_test" 2>/dev/null; then
        rm "$MOUNT_POINT/.gcsfuse_test"
        log "Prueba de Lectura/Escritura superada."
    else
        warn "El bucket está montado, pero tu usuario actual NO tiene permisos de escritura."
        warn "Revisa los roles de tu Service Account en GCP (necesita Storage Object Admin)."
    fi
else
    error "El montaje falló. Revisa el log de errores con:\ncat $LOG_FILE"
fi

### ===== 7. PERSISTENCIA =====
step "Configuración de Arranque"

read -p "¿Deseas hacerlo persistente al reiniciar? [y/N]: " persist

if [[ "$persist" =~ ^[Yy]$ ]]; then
    FSTAB_LINE="$BUCKET_NAME $MOUNT_POINT gcsfuse rw,_netdev,allow_other,dir_mode=0777,file_mode=0777,--implicit-dirs,--key-file=$KEY_FILE 0 0"

    # Limpiamos entradas viejas para evitar duplicados
    sudo sed -i "|$MOUNT_POINT|d" /etc/fstab
    
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
    log "Entrada actualizada en /etc/fstab"
    warn "Nota: Si la VM arranca sin internet, el boot podría demorar. /etc/fstab espera a la red (_netdev)."
fi

step "Proceso finalizado con éxito ✅"
