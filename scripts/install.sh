#!/bin/bash

# ==============================================================================
# Proyecto Netflix - Script de Instalación y Configuración Base
# Objetivo: Preparar entorno ARM64, Tailscale Exit Node y servicio PicoClaw
# ==============================================================================

# Obtener la ruta absoluta del repositorio (un nivel arriba de /scripts)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Iniciando configuración..."
echo "Directorio del repositorio: $REPO_DIR"

# 1. Habilitar IP Forwarding (Requisito indispensable para Tailscale Exit Node)
echo "Configurando IP Forwarding..."
SYSCTL_CONF="/etc/sysctl.d/99-tailscale.conf"

# Evitar duplicados: solo añadir si la línea no existe ya
grep -qxF 'net.ipv4.ip_forward = 1' "$SYSCTL_CONF" 2>/dev/null || \
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a "$SYSCTL_CONF"

grep -qxF 'net.ipv6.conf.all.forwarding = 1' "$SYSCTL_CONF" 2>/dev/null || \
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a "$SYSCTL_CONF"

sudo sysctl -p "$SYSCTL_CONF"

# 2. Instalar Tailscale (si no está instalado)
if ! command -v tailscale &> /dev/null; then
    echo "Tailscale no encontrado. Instalando..."
    curl -fsSL https://tailscale.com/install.sh | sh
else
    echo "Tailscale ya está instalado."
fi

# 3. Descargar e instalar PicoClaw desde paquete .deb
PICOCLAW_DEB="/tmp/picoclaw_aarch64.deb"
PICOCLAW_URL="https://github.com/sipeed/picoclaw/releases/download/v0.2.4/picoclaw_aarch64.deb"

if command -v picoclaw &> /dev/null; then
    echo "PicoClaw ya está instalado."
else
    echo "Descargando PicoClaw desde GitHub..."
    if command -v wget &> /dev/null; then
        wget "$PICOCLAW_URL" -O "$PICOCLAW_DEB"
    elif command -v curl &> /dev/null; then
        curl -fsSL "$PICOCLAW_URL" -o "$PICOCLAW_DEB"
    else
        echo "Error: se necesita wget o curl para descargar PicoClaw."
        exit 1
    fi

    if [ ! -s "$PICOCLAW_DEB" ]; then
        echo "Error: la descarga falló o el archivo está vacío. Abortando."
        rm -f "$PICOCLAW_DEB"
        exit 1
    fi

    echo "Instalando PicoClaw..."
    sudo dpkg -i "$PICOCLAW_DEB"
    rm -f "$PICOCLAW_DEB"

    if ! command -v picoclaw &> /dev/null; then
        echo "Error: la instalación del paquete falló. Abortando."
        exit 1
    fi
    echo "PicoClaw instalado correctamente."
fi

# 4. Crear usuario dedicado para PicoClaw (sin shell ni directorio home)
if ! id "picoclaw" &>/dev/null; then
    echo "Creando usuario 'picoclaw'..."
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin picoclaw
    echo "Usuario 'picoclaw' creado."
fi

# 5. Configurar e iniciar el servicio Systemd para PicoClaw
SERVICE_FILE="$REPO_DIR/config/picoclaw.service"
echo "Configurando PicoClaw como servicio..."

if [ -f "$SERVICE_FILE" ]; then
    sudo cp "$SERVICE_FILE" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable picoclaw.service
    sudo systemctl start picoclaw.service
    echo "Servicio PicoClaw iniciado correctamente."
else
    echo "Advertencia: Archivo picoclaw.service no encontrado en $REPO_DIR/config/"
fi

echo "¡Configuración base completada!"
echo "Recuerda ejecutar: sudo tailscale up --advertise-exit-node"
