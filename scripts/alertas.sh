#!/bin/bash

# ==============================================================================
# Sistema de Alertas vía Telegram
# Monitoriza los servicios y envía notificaciones si algo falla
# Uso como cron: */5 * * * * /bin/bash /ruta/alertas.sh
# ==============================================================================

# --- CONFIGURACIÓN ---
# Rellena estos valores con los datos de tu bot de Telegram
# Guía rápida:
#   1. Habla con @BotFather en Telegram y crea un bot → obtendrás el TOKEN
#   2. Habla con @userinfobot → obtendrás tu CHAT_ID
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""

# Archivo para evitar enviar la misma alerta repetidamente
STATE_FILE="/tmp/alertas_estado.txt"

# --- FUNCIONES ---
enviar_telegram() {
    local mensaje="$1"
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Advertencia: TELEGRAM_TOKEN o TELEGRAM_CHAT_ID no configurados."
        return 1
    fi
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="Markdown" \
        -d text="$mensaje" > /dev/null
}

alerta() {
    local clave="$1"
    local mensaje="$2"
    # Solo envía la alerta si no se ha enviado ya (evita spam)
    if ! grep -qx "$clave" "$STATE_FILE" 2>/dev/null; then
        enviar_telegram "$mensaje"
        echo "$clave" >> "$STATE_FILE"
    fi
}

recuperacion() {
    local clave="$1"
    local mensaje="$2"
    # Solo notifica recuperación si antes había una alerta activa
    if grep -qx "$clave" "$STATE_FILE" 2>/dev/null; then
        enviar_telegram "$mensaje"
        sed -i "/$clave/d" "$STATE_FILE"
    fi
}

HOSTNAME=$(hostname)

# --- COMPROBACIONES ---

# 1. Servicio PicoClaw
if ! systemctl is-active --quiet picoclaw.service; then
    alerta "picoclaw_caido" \
        "🔴 *ALERTA — $HOSTNAME*
Servicio \`picoclaw\` caído o reiniciado.
\`sudo systemctl status picoclaw.service\`"
else
    recuperacion "picoclaw_caido" \
        "✅ *RECUPERADO — $HOSTNAME*
Servicio \`picoclaw\` vuelve a estar activo."
fi

# 2. Servicio Tailscale
if ! systemctl is-active --quiet tailscaled; then
    alerta "tailscale_caido" \
        "🔴 *ALERTA — $HOSTNAME*
Servicio \`tailscaled\` caído.
\`sudo systemctl status tailscaled\`"
else
    recuperacion "tailscale_caido" \
        "✅ *RECUPERADO — $HOSTNAME*
Servicio \`tailscaled\` vuelve a estar activo."
fi

# 3. Conectividad a internet
if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
    alerta "sin_internet" \
        "🌐 *ALERTA — $HOSTNAME*
Sin conexión a internet detectada."
else
    recuperacion "sin_internet" \
        "✅ *RECUPERADO — $HOSTNAME*
Conexión a internet restaurada."
fi

# 4. Uso de disco > 90%
USO_DISCO=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$USO_DISCO" -gt 90 ]; then
    alerta "disco_lleno" \
        "💾 *ALERTA — $HOSTNAME*
Disco al ${USO_DISCO}% de capacidad.
Libera espacio para evitar fallos."
else
    recuperacion "disco_lleno" \
        "✅ *RECUPERADO — $HOSTNAME*
Uso de disco normalizado: ${USO_DISCO}%."
fi

# 5. Temperatura CPU > 80°C (solo Raspberry Pi)
if command -v vcgencmd &>/dev/null; then
    TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -o '[0-9]*\.[0-9]*')
    TEMP_INT=${TEMP%.*}
    if [ "$TEMP_INT" -gt 80 ]; then
        alerta "temperatura_alta" \
            "🌡️ *ALERTA — $HOSTNAME*
Temperatura CPU crítica: ${TEMP}°C
Comprueba la ventilación de la placa."
    else
        recuperacion "temperatura_alta" \
            "✅ *RECUPERADO — $HOSTNAME*
Temperatura CPU normalizada: ${TEMP}°C."
    fi
fi
