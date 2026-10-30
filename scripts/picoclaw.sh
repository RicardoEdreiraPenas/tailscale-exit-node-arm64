#!/usr/bin/env bash
# PicoClaw: asistente de estado por Telegram (opcional).
#
# Uso:
#   sudo bash scripts/picoclaw.sh instalar      instala, pide token/ID/API key, aplica la configuración segura y arranca
#   sudo bash scripts/picoclaw.sh configurar    vuelve a pedir token, ID de Telegram, API key y modelo
#   sudo bash scripts/picoclaw.sh endurecer     reaplica la configuración segura (p. ej. tras editarla a mano)
#   sudo bash scripts/picoclaw.sh actualizar    instala la versión fijada en versiones.conf conservando la configuración
#   sudo bash scripts/picoclaw.sh desinstalar
#
# Por defecto el asistente NO puede ejecutar comandos: lee un informe de estado
# que se regenera cada minuto. Ver SECURITY.md para el porqué.
#
# Todo lo que toca la carpeta del usuario picoclaw se hace como ese usuario, nunca como root:
# si alguien lo comprometiera, no podría usar enlaces simbólicos para que root escriba donde no debe.

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"

ACCION=""
PERMITIR_COMANDOS=0
for arg in "$@"; do
    case "$arg" in
        --permitir-comandos) PERMITIR_COMANDOS=1 ;;
        --simular) SIMULAR=1 ;;
        *) ACCION="$arg" ;;
    esac
done

requiere_root
cargar_versiones

HOME_PC=/var/lib/picoclaw
WS="$HOME_PC/workspace"
ENDURECER=/usr/local/lib/exitnode/picoclaw_endurecer.py

instalar_paquete() {
    titulo "PicoClaw $PICOCLAW_VERSION"
    [[ "$(arquitectura)" == "arm64" ]] || morir "El paquete de PicoClaw que se instala es para ARM64."
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    descargar_verificado \
        "https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}/picoclaw_aarch64.deb" \
        "$tmp/picoclaw.deb" "$PICOCLAW_SHA256_ARM64_DEB"
    ejecutar systemctl disable --now picoclaw.service 2>/dev/null || true
    ejecutar dpkg -i "$tmp/picoclaw.deb"

    if ! id picoclaw >/dev/null 2>&1; then
        ejecutar useradd --system --home-dir "$HOME_PC" --create-home --shell /usr/sbin/nologin picoclaw
    fi
    # La carpeta personal la crea useradd; root no crea nada dentro.
    sin_enlaces "$(r "$HOME_PC")"
    ejecutar chmod 0700 "$(r "$HOME_PC")"

    # Copia del script de configuración en una ruta de root (el usuario picoclaw solo puede leerlo).
    ejecutar install -d -m 0755 "$(r /usr/local/lib/exitnode)"
    ejecutar install -m 0755 "$DIR_REPO/scripts/picoclaw_endurecer.py" "$(r "$ENDURECER")"
    ejecutar install -m 0644 "$DIR_REPO/config/plantillas/picoclaw_AGENT.md" "$(r /usr/local/lib/exitnode/picoclaw_AGENT.md)"
}

instalar() {
    instalar_paquete

    # Configuración por defecto y carpeta de trabajo, creadas por el propio usuario picoclaw.
    if [[ ! -f "$(r "$HOME_PC/.picoclaw/config.json")" ]]; then
        como_usuario picoclaw env HOME="$HOME_PC" picoclaw onboard </dev/null
    fi
    como_usuario picoclaw sh -c "umask 027; mkdir -p '$WS' && cp /usr/local/lib/exitnode/picoclaw_AGENT.md '$WS/AGENT.md'"

    escribir_fichero /etc/systemd/system/picoclaw.service 0644 <"$DIR_REPO/config/systemd/picoclaw.service"
    escribir_fichero /etc/systemd/system/picoclaw-estado.service 0644 <"$DIR_REPO/config/systemd/picoclaw-estado.service"
    escribir_fichero /etc/systemd/system/picoclaw-estado.timer 0644 <"$DIR_REPO/config/systemd/picoclaw-estado.timer"
    ejecutar systemctl daemon-reload
    ejecutar systemctl enable --now picoclaw-estado.timer
    guardar_config PICOCLAW si

    configurar
}

configurar() {
    titulo "Telegram y modelo de IA"
    local token chat clave modelo
    echo "  1. Bot: habla con @BotFather en Telegram, escribe /newbot y copia el token."
    echo "  2. Tu ID: escribe a @userinfobot y copia el número."
    echo "  3. API key de Google AI Studio: https://aistudio.google.com -> Get API key."
    if [[ "$SIMULAR" == "1" ]]; then
        printf '  [simulado] se pedirían token, ID y API key\n'
        endurecer
        return
    fi
    read -r -s -p "  Token del bot: " token; echo
    read -r -p "  Tu ID numérico de Telegram: " chat
    read -r -s -p "  API key de Gemini: " clave; echo
    read -r -p "  Modelo [gemini-2.5-flash]: " modelo
    modelo="${modelo:-gemini-2.5-flash}"
    [[ "$token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || morir "El token no tiene el formato esperado."
    [[ "$chat" =~ ^-?[0-9]{5,15}$ ]] || morir "El ID de Telegram debe ser numérico."
    [[ -n "$clave" ]] || morir "Falta la API key."
    [[ "$modelo" =~ ^[A-Za-z0-9._-]+$ ]] || morir "Nombre de modelo no válido."
    # Los secretos llegan al script por la entrada estándar: no aparecen en la lista de procesos.
    jq -n --arg t "$token" --arg c "$chat" --arg k "$clave" --arg m "$modelo" \
        '{token: $t, chat_id: $c, api_key: $k, modelo: $m}' \
        | aplicar_endurecimiento --configurar
    arrancar
}

aplicar_endurecimiento() {
    local extra=("$@")
    [[ "$PERMITIR_COMANDOS" == "1" ]] && extra+=(--permitir-comandos)
    como_usuario picoclaw env HOME="$HOME_PC" python3 -I "$ENDURECER" \
        --home "$HOME_PC/.picoclaw" --workspace "$WS" "${extra[@]}"
}

endurecer() {
    titulo "Configuración segura de PicoClaw"
    if ! aplicar_endurecimiento </dev/null; then
        ejecutar systemctl disable --now picoclaw.service 2>/dev/null || true
        morir "Corrige lo anterior (sudo bash scripts/picoclaw.sh configurar). El servicio queda parado."
    fi
    arrancar
}

arrancar() {
    ejecutar systemctl enable picoclaw.service
    ejecutar systemctl restart picoclaw.service
    ok "PicoClaw arrancado con la configuración segura. Escríbele a tu bot: ¿cómo está el sistema?"
}

desinstalar() {
    titulo "Desinstalar PicoClaw"
    ejecutar systemctl disable --now picoclaw.service picoclaw-estado.timer 2>/dev/null || true
    ejecutar rm -f "$(r /etc/systemd/system/picoclaw.service)" \
                   "$(r /etc/systemd/system/picoclaw-estado.service)" \
                   "$(r /etc/systemd/system/picoclaw-estado.timer)" \
                   "$(r "$ENDURECER")" "$(r /usr/local/lib/exitnode/picoclaw_AGENT.md)"
    ejecutar systemctl daemon-reload
    if dpkg -s picoclaw >/dev/null 2>&1; then
        ejecutar dpkg -r picoclaw
    fi
    if id picoclaw >/dev/null 2>&1 && confirmar "¿Borrar también su configuración y secretos ($HOME_PC)?" s; then
        ejecutar userdel -r picoclaw 2>/dev/null || true
    fi
    guardar_config PICOCLAW no
    ok "PicoClaw desinstalado"
}

case "$ACCION" in
    instalar) instalar ;;
    configurar) configurar ;;
    endurecer) endurecer ;;
    actualizar) instalar_paquete; endurecer ;;
    desinstalar) desinstalar ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
