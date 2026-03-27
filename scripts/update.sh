#!/bin/bash

# ==============================================================================
# Script de Actualización
# Actualiza Tailscale y PicoClaw a sus últimas versiones
# ==============================================================================

PICOCLAW_URL="https://github.com/sipeed/picoclaw/releases/download/v0.2.4/picoclaw-linux-arm64"

echo "Iniciando actualización del sistema..."

# 1. Actualizar paquetes del sistema y Tailscale
echo ""
echo "[ 1/2 ] Actualizando Tailscale..."
sudo apt update -q
if sudo apt upgrade tailscale -y; then
    echo "Tailscale actualizado correctamente."
    VERSION=$(tailscale version 2>/dev/null | head -1)
    echo "Versión activa: $VERSION"
    sudo systemctl restart tailscaled
    echo "Servicio tailscaled reiniciado."
else
    echo "Advertencia: no se pudo actualizar Tailscale desde apt."
fi

# 2. Actualizar PicoClaw
echo ""
echo "[ 2/2 ] Actualizando PicoClaw..."

TMP_BIN=$(mktemp)

if command -v wget &>/dev/null; then
    wget -q "$PICOCLAW_URL" -O "$TMP_BIN"
elif command -v curl &>/dev/null; then
    curl -fsSL "$PICOCLAW_URL" -o "$TMP_BIN"
else
    echo "Error: se necesita wget o curl para descargar PicoClaw."
    rm -f "$TMP_BIN"
    exit 1
fi

if [ -s "$TMP_BIN" ]; then
    sudo systemctl stop picoclaw.service 2>/dev/null
    sudo chmod +x "$TMP_BIN"
    sudo mv "$TMP_BIN" /usr/local/bin/picoclaw
    sudo systemctl start picoclaw.service
    echo "PicoClaw actualizado e iniciado correctamente."
else
    echo "Error: la descarga de PicoClaw falló o el archivo está vacío."
    rm -f "$TMP_BIN"
    exit 1
fi

echo ""
echo "Actualización completada."
echo "Ejecuta 'bash scripts/status.sh' para verificar el estado del sistema."
