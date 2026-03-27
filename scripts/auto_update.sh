#!/bin/bash

# ==============================================================================
# Actualizador Automático con Cron
# Comprueba si hay nueva versión de PicoClaw y actualiza si es necesario
# También puede instalarse como tarea cron para ejecución periódica
# ==============================================================================

PICOCLAW_URL="https://github.com/sipeed/picoclaw/releases/download/v0.2.4/picoclaw_aarch64.deb"
LOG_FILE="/var/log/picoclaw_update.log"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE"; }

# --- Modo instalación del cron ---
if [ "$1" = "--instalar-cron" ]; then
    CRON_JOB="0 4 * * * /bin/bash $SCRIPT_PATH >> $LOG_FILE 2>&1"
    ( crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_JOB" ) | crontab -
    echo "Cron instalado: actualizacion automatica todos los dias a las 04:00"
    echo "Logs en: $LOG_FILE"
    exit 0
fi

if [ "$1" = "--desinstalar-cron" ]; then
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo "Cron de actualizacion automatica eliminado."
    exit 0
fi

# --- Lógica de actualización ---
log "Comprobando actualizaciones de PicoClaw..."

# Obtener el hash MD5 de la versión instalada
HASH_ACTUAL=""
if [ -f /usr/local/bin/picoclaw ]; then
    HASH_ACTUAL=$(md5sum /usr/local/bin/picoclaw | awk '{print $1}')
fi

# Descargar la última versión a un archivo temporal
TMP_BIN=$(mktemp)

if command -v wget &>/dev/null; then
    wget -q "$PICOCLAW_URL" -O "$TMP_BIN"
elif command -v curl &>/dev/null; then
    curl -fsSL "$PICOCLAW_URL" -o "$TMP_BIN"
else
    log "Error: se necesita wget o curl."
    rm -f "$TMP_BIN"
    exit 1
fi

if [ ! -s "$TMP_BIN" ]; then
    log "Error: la descarga falló o el archivo está vacío."
    rm -f "$TMP_BIN"
    exit 1
fi

HASH_NUEVO=$(md5sum "$TMP_BIN" | awk '{print $1}')

# Comparar hashes para saber si hay cambio real
if [ "$HASH_ACTUAL" = "$HASH_NUEVO" ]; then
    log "PicoClaw ya está en la última versión. Sin cambios."
    rm -f "$TMP_BIN"
    exit 0
fi

log "Nueva versión detectada. Actualizando..."

sudo systemctl stop picoclaw.service 2>/dev/null
sudo chmod +x "$TMP_BIN"
sudo mv "$TMP_BIN" /usr/local/bin/picoclaw
sudo systemctl start picoclaw.service

if systemctl is-active --quiet picoclaw.service; then
    log "PicoClaw actualizado e iniciado correctamente."
else
    log "Advertencia: PicoClaw actualizado pero el servicio no arrancó. Revisa: journalctl -u picoclaw.service"
fi
