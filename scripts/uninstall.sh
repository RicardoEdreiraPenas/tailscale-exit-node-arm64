#!/bin/bash

# ==============================================================================
# Script de Desinstalación Completa
# Elimina PicoClaw, su servicio y la configuración de IP Forwarding
# ==============================================================================

echo "Iniciando desinstalación..."

# 1. Detener y deshabilitar el servicio PicoClaw
if systemctl is-active --quiet picoclaw.service; then
    echo "Deteniendo servicio PicoClaw..."
    sudo systemctl stop picoclaw.service
fi

if systemctl is-enabled --quiet picoclaw.service 2>/dev/null; then
    echo "Deshabilitando servicio PicoClaw..."
    sudo systemctl disable picoclaw.service
fi

# 2. Eliminar archivos del servicio y binario
echo "Eliminando archivos instalados..."

[ -f /etc/systemd/system/picoclaw.service ] && sudo rm /etc/systemd/system/picoclaw.service
[ -f /usr/local/bin/picoclaw ]              && sudo rm /usr/local/bin/picoclaw

sudo systemctl daemon-reload

# 3. Eliminar usuario dedicado si existe
if id "picoclaw" &>/dev/null; then
    echo "Eliminando usuario 'picoclaw'..."
    sudo userdel picoclaw
fi

# 4. Revertir IP Forwarding
echo "Revirtiendo configuración de IP Forwarding..."
[ -f /etc/sysctl.d/99-tailscale.conf ] && sudo rm /etc/sysctl.d/99-tailscale.conf
sudo sysctl -w net.ipv4.ip_forward=0
sudo sysctl -w net.ipv6.conf.all.forwarding=0

# 5. Preguntar si desea desinstalar Tailscale
read -r -p "¿Deseas desinstalar también Tailscale? [s/N] " respuesta
if [[ "$respuesta" =~ ^[sS]$ ]]; then
    echo "Desinstalando Tailscale..."
    sudo apt remove --purge tailscale -y
    sudo rm -f /etc/apt/sources.list.d/tailscale.list
    sudo apt autoremove -y
    echo "Tailscale desinstalado."
else
    echo "Tailscale conservado."
fi

echo "Desinstalación completada."
