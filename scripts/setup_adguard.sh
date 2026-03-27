#!/bin/bash

# ==============================================================================
# Instalación de AdGuard Home con integración Tailscale (MagicDNS)
# Bloquea anuncios y rastreadores en todos los dispositivos de la red
# ==============================================================================

ADGUARD_DIR="/opt/AdGuardHome"

echo "Iniciando instalación de AdGuard Home..."

# 1. Descargar e instalar AdGuard Home
if [ -d "$ADGUARD_DIR" ]; then
    echo "AdGuard Home ya está instalado en $ADGUARD_DIR"
else
    echo "Descargando AdGuard Home para ARM64..."
    TMP_DIR=$(mktemp -d)

    if command -v wget &>/dev/null; then
        wget -q "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz" -O "$TMP_DIR/adguard.tar.gz"
    elif command -v curl &>/dev/null; then
        curl -fsSL "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz" -o "$TMP_DIR/adguard.tar.gz"
    else
        echo "Error: se necesita wget o curl."
        exit 1
    fi

    tar -xzf "$TMP_DIR/adguard.tar.gz" -C "$TMP_DIR"
    sudo mv "$TMP_DIR/AdGuardHome" "$ADGUARD_DIR"
    rm -rf "$TMP_DIR"
    echo "AdGuard Home descargado en $ADGUARD_DIR"
fi

# 2. Instalar como servicio systemd
if ! systemctl is-enabled --quiet AdGuardHome 2>/dev/null; then
    echo "Instalando AdGuard Home como servicio..."
    sudo "$ADGUARD_DIR/AdGuardHome" -s install
    echo "Servicio AdGuardHome instalado."
fi

# 3. Iniciar el servicio
sudo systemctl enable AdGuardHome
sudo systemctl start AdGuardHome

if systemctl is-active --quiet AdGuardHome; then
    echo "AdGuard Home activo correctamente."
else
    echo "Error: AdGuard Home no pudo iniciarse."
    exit 1
fi

# 4. Instrucciones de configuración
IP_LOCAL=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo "  AdGuard Home instalado. Pasos para completar la config:"
echo "============================================================"
echo ""
echo "  1. Abre en tu navegador: http://$IP_LOCAL:3000"
echo "     (asistente de configuración inicial)"
echo ""
echo "  2. Durante la configuración, elige el puerto DNS: 53"
echo "     y el puerto web: 80 (o 3000 si el 80 está ocupado)"
echo ""
echo "  3. En Tailscale, activa MagicDNS:"
echo "     https://login.tailscale.com/admin/dns"
echo "     → 'Add nameserver' → IP Tailscale de esta placa"
echo "     → Activa 'Override local DNS'"
echo ""
echo "  4. Reinicia Tailscale para aplicar el DNS:"
echo "     sudo tailscale up --advertise-exit-node --advertise-routes=$(hostname -I | awk '{print $1}')/32"
echo ""
