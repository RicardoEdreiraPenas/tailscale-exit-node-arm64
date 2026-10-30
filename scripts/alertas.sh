#!/usr/bin/env bash
# Alertas por Telegram cuando algo falla en el exit node.
#
# Uso:
#   sudo bash scripts/alertas.sh --configurar   guarda el token y el chat, envía una prueba y activa el temporizador
#   sudo bash scripts/alertas.sh --desactivar
#   alertas.sh --comprobar                      lo ejecuta systemd cada 5 minutos (no hace falta lanzarlo a mano)
#
# El token se guarda en /etc/exitnode/alertas.env (solo legible por root). systemd lo
# lee al arrancar la comprobación, que corre con un usuario temporal sin privilegios.

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"

MODO="${1:---comprobar}"
ENV_FILE="$DIR_CONF/alertas.env"
ESTADO="${STATE_DIRECTORY:-/var/lib/exitnode-alertas}/activas"

# Envía un mensaje sin poner el token en la línea de comandos (no aparece en 'ps').
enviar_telegram() {
    local texto="$1"
    [[ -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || { error "Faltan TELEGRAM_TOKEN o TELEGRAM_CHAT_ID"; return 1; }
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_TOKEN" \
        | curl --fail --silent --show-error --max-time 15 --proto '=https' --config - \
               --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
               --data-urlencode "text=${texto}" >/dev/null
}

# Avisa una sola vez por problema y otra vez cuando se resuelve.
alerta() {
    local clave="$1" texto="$2"
    grep -qxF "$clave" "$ESTADO" 2>/dev/null && return 0
    enviar_telegram "🔴 $(hostname): $texto" && echo "$clave" >>"$ESTADO"
}
resuelto() {
    local clave="$1" texto="$2"
    grep -qxF "$clave" "$ESTADO" 2>/dev/null || return 0
    if enviar_telegram "✅ $(hostname): $texto"; then
        grep -vxF "$clave" "$ESTADO" >"$ESTADO.tmp" || true
        mv -f "$ESTADO.tmp" "$ESTADO"
    fi
}
comprobar_servicio() {
    local svc="$1" nombre="$2"
    if servicio_activo "$svc"; then
        resuelto "svc_$svc" "$nombre vuelve a funcionar."
    else
        alerta "svc_$svc" "$nombre está parado. Revisa: sudo systemctl status $svc"
    fi
}

comprobar() {
    mkdir -p "$(dirname "$ESTADO")"
    touch "$ESTADO"
    leer_config

    comprobar_servicio tailscaled "Tailscale"
    case "$BLOQUEADOR" in
        adguard) comprobar_servicio adguardhome "AdGuard Home" ;;
        pihole)  comprobar_servicio pihole-FTL "Pi-hole" ;;
    esac
    if [[ "${PICOCLAW:-no}" == "si" ]]; then
        comprobar_servicio picoclaw "PicoClaw"
    fi

    if curl --silent --head --max-time 10 --proto '=https' https://api.telegram.org >/dev/null; then
        resuelto internet "Vuelve a haber internet. Hubo un corte desde $(cat "$ESTADO.internet" 2>/dev/null || echo 'hace un rato')."
        rm -f "$ESTADO.internet"
    elif ! grep -qxF internet "$ESTADO"; then
        # Sin internet el aviso no puede salir: se apunta el corte y se avisa al volver.
        echo internet >>"$ESTADO"
        date '+%d/%m %H:%M' >"$ESTADO.internet"
    fi

    local disco
    disco="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
    if (( disco > 90 )); then
        alerta disco "Disco al ${disco}%. Libera espacio para evitar fallos."
    else
        resuelto disco "Uso de disco normal (${disco}%)."
    fi

    local t
    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        t=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
        if (( t > 80 )); then
            alerta temperatura "Temperatura de la CPU en ${t} °C. Revisa la ventilación."
        elif (( t < 75 )); then
            resuelto temperatura "Temperatura normal (${t} °C)."
        fi
    fi
}

configurar() {
    requiere_root
    local token chat
    echo "  1. En Telegram, habla con @BotFather, escribe /newbot y copia el token."
    echo "  2. Habla con @userinfobot y copia tu ID numérico."
    read -r -s -p "  Token del bot: " token; echo
    read -r -p "  Tu ID numérico de Telegram: " chat
    [[ "$token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || morir "El token no tiene el formato esperado."
    [[ "$chat" =~ ^-?[0-9]{5,15}$ ]] || morir "El ID debe ser numérico."
    install -d -m 0755 "$DIR_CONF"
    ( umask 077; printf 'TELEGRAM_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$token" "$chat" >"$ENV_FILE" )
    chmod 0600 "$ENV_FILE"
    TELEGRAM_TOKEN="$token" TELEGRAM_CHAT_ID="$chat" enviar_telegram "Alertas del exit node configuradas en $(hostname)." \
        || morir "No se pudo enviar el mensaje de prueba. Revisa el token y que hayas escrito antes al bot."
    systemctl enable --now exitnode-alertas.timer
    ok "Alertas activas. Te ha llegado un mensaje de prueba."
}

desactivar() {
    requiere_root
    systemctl disable --now exitnode-alertas.timer 2>/dev/null || true
    rm -f "$ENV_FILE"
    ok "Alertas desactivadas y token borrado."
}

case "$MODO" in
    --comprobar)  comprobar ;;
    --configurar) configurar ;;
    --desactivar) desactivar ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
