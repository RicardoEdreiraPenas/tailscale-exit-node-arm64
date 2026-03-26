#!/bin/bash

# ==============================================================================
# Panel de Estado del Sistema
# Muestra el estado de todos los componentes de un vistazo
# ==============================================================================

VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
RESET='\033[0m'
NEGRITA='\033[1m'

ok()   { echo -e "  ${VERDE}[OK]${RESET}    $1"; }
fallo(){ echo -e "  ${ROJO}[ERROR]${RESET} $1"; }
aviso(){ echo -e "  ${AMARILLO}[AVISO]${RESET} $1"; }

echo ""
echo -e "${NEGRITA}================================================${RESET}"
echo -e "${NEGRITA}   ESTADO DEL SISTEMA — Tailscale Exit Node   ${RESET}"
echo -e "${NEGRITA}================================================${RESET}"

# --- IP Forwarding ---
echo ""
echo -e "${NEGRITA}[ IP Forwarding ]${RESET}"
IPV4=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
IPV6=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)
[ "$IPV4" = "1" ] && ok "IPv4 forwarding activo" || fallo "IPv4 forwarding INACTIVO"
[ "$IPV6" = "1" ] && ok "IPv6 forwarding activo" || fallo "IPv6 forwarding INACTIVO"

# --- Tailscale ---
echo ""
echo -e "${NEGRITA}[ Tailscale ]${RESET}"
if systemctl is-active --quiet tailscaled; then
    ok "Servicio tailscaled activo"
    if command -v tailscale &>/dev/null; then
        TSVERSION=$(tailscale version 2>/dev/null | head -1)
        ok "Versión: $TSVERSION"
        if tailscale status &>/dev/null; then
            ok "Conectado a la red Tailscale"
            # Verificar si está anunciando como exit node
            if tailscale status --json 2>/dev/null | grep -q '"ExitNodeOption":true'; then
                ok "Exit node activo y anunciado"
            else
                aviso "Exit node NO anunciado. Ejecuta: sudo tailscale up --advertise-exit-node"
            fi
        else
            aviso "No autenticado. Ejecuta: sudo tailscale up --advertise-exit-node"
        fi
    fi
else
    fallo "Servicio tailscaled INACTIVO"
fi

# --- PicoClaw ---
echo ""
echo -e "${NEGRITA}[ PicoClaw ]${RESET}"
if [ -f /usr/local/bin/picoclaw ]; then
    ok "Binario instalado en /usr/local/bin/picoclaw"
else
    fallo "Binario NO encontrado en /usr/local/bin/"
fi

if systemctl is-active --quiet picoclaw.service; then
    ok "Servicio picoclaw activo"
    UPTIME=$(systemctl show picoclaw.service --property=ActiveEnterTimestamp | cut -d= -f2)
    ok "Activo desde: $UPTIME"
else
    fallo "Servicio picoclaw INACTIVO"
    aviso "Para iniciar: sudo systemctl start picoclaw.service"
fi

# --- Sistema ---
echo ""
echo -e "${NEGRITA}[ Sistema ]${RESET}"

# Uptime
UPTIME_SYS=$(uptime -p 2>/dev/null || uptime)
ok "Uptime: $UPTIME_SYS"

# Temperatura (solo Raspberry Pi)
if command -v vcgencmd &>/dev/null; then
    TEMP=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2)
    ok "Temperatura CPU: $TEMP"
fi

# Memoria
MEM=$(free -h | awk '/^Mem:/ {print "Usada: "$3" / Total: "$2}')
ok "Memoria RAM — $MEM"

# Disco
DISCO=$(df -h / | awk 'NR==2 {print "Usada: "$3" / Total: "$2" ("$5")"}')
ok "Disco — $DISCO"

# IP local
IP_LOCAL=$(hostname -I | awk '{print $1}')
ok "IP local: $IP_LOCAL"

# --- Ancho de Banda (vnStat) ---
echo ""
echo -e "${NEGRITA}[ Ancho de Banda ]${RESET}"
if command -v vnstat &>/dev/null; then
    IFACE=$(ip route | awk '/default/ {print $5}' | head -1)
    HOY=$(vnstat -i "$IFACE" --oneline 2>/dev/null | awk -F';' '{print "Hoy: "$10" rx / "$11" tx"}')
    MES=$(vnstat -i "$IFACE" --oneline 2>/dev/null | awk -F';' '{print "Mes: "$15" rx / "$16" tx"}')
    ok "$HOY"
    ok "$MES"
else
    aviso "vnStat no instalado. Para activar monitorización: sudo apt install vnstat -y"
fi

# --- AdGuard Home ---
echo ""
echo -e "${NEGRITA}[ AdGuard Home ]${RESET}"
if systemctl is-active --quiet AdGuardHome; then
    ok "Servicio AdGuard Home activo"
else
    aviso "AdGuard Home no activo. Para instalarlo: bash scripts/setup_adguard.sh"
fi

echo ""
echo -e "${NEGRITA}================================================${RESET}"
echo ""
