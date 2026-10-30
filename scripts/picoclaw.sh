#!/usr/bin/env bash
# PicoClaw: asistente de estado por Telegram (opcional).
#
# Uso:
#   sudo bash scripts/picoclaw.sh instalar      descarga verificada, usuario propio y servicio aislado
#   sudo bash scripts/picoclaw.sh endurecer     tras 'picoclaw onboard': aplica la configuración segura y arranca
#   sudo bash scripts/picoclaw.sh desinstalar
#
# Por defecto el asistente NO puede ejecutar comandos: lee un informe de estado
# que se regenera cada minuto. Ver SECURITY.md para el porqué.

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"

ACCION="${1:-}"
PERMITIR_COMANDOS=0
for arg in "$@"; do
    case "$arg" in
        --permitir-comandos) PERMITIR_COMANDOS=1 ;;
        --simular) SIMULAR=1 ;;
    esac
done

requiere_root
cargar_versiones

HOME_PC=/var/lib/picoclaw
WS="$HOME_PC/workspace"

instalar() {
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
    ejecutar install -d -m 0700 -o picoclaw -g picoclaw "$(r "$HOME_PC")"
    ejecutar install -d -m 0750 -o picoclaw -g picoclaw "$(r "$WS")"
    escribir_fichero "$WS/AGENT.md" 0640 picoclaw:picoclaw <"$DIR_REPO/config/plantillas/picoclaw_AGENT.md"

    escribir_fichero /etc/systemd/system/picoclaw.service 0644 <"$DIR_REPO/config/systemd/picoclaw.service"
    escribir_fichero /etc/systemd/system/picoclaw-estado.service 0644 <"$DIR_REPO/config/systemd/picoclaw-estado.service"
    escribir_fichero /etc/systemd/system/picoclaw-estado.timer 0644 <"$DIR_REPO/config/systemd/picoclaw-estado.timer"
    ejecutar systemctl daemon-reload
    ejecutar systemctl enable --now picoclaw-estado.timer
    guardar_config PICOCLAW si

    cat <<EOF

  PicoClaw instalado, pero todavía no arranca. Faltan dos pasos:

  1. Asistente de configuración (Telegram + modelo de IA), con el usuario propio:
       sudo -u picoclaw -H picoclaw onboard
     En "allow_from" pon tu ID numérico de Telegram (te lo da @userinfobot).

  2. Aplicar la configuración segura y arrancar:
       sudo bash scripts/picoclaw.sh endurecer

EOF
}

endurecer() {
    titulo "Configuración segura de PicoClaw"
    local extra=()
    [[ "$PERMITIR_COMANDOS" == "1" ]] && extra+=(--permitir-comandos)
    if ! python3 "$DIR_REPO/scripts/picoclaw_endurecer.py" --home "$(r "$HOME_PC/.picoclaw")" --workspace "$WS" "${extra[@]}"; then
        ejecutar systemctl disable --now picoclaw.service 2>/dev/null || true
        morir "Corrige lo anterior (sudo -u picoclaw -H picoclaw onboard) y vuelve a ejecutar 'endurecer'. El servicio queda parado."
    fi
    ejecutar chown -R picoclaw:picoclaw "$(r "$HOME_PC/.picoclaw")"
    ejecutar systemctl enable picoclaw.service
    ejecutar systemctl restart picoclaw.service
    ok "PicoClaw arrancado con la configuración segura"
}

desinstalar() {
    titulo "Desinstalar PicoClaw"
    ejecutar systemctl disable --now picoclaw.service picoclaw-estado.timer 2>/dev/null || true
    ejecutar rm -f "$(r /etc/systemd/system/picoclaw.service)" \
                   "$(r /etc/systemd/system/picoclaw-estado.service)" \
                   "$(r /etc/systemd/system/picoclaw-estado.timer)"
    ejecutar systemctl daemon-reload
    if dpkg -s picoclaw >/dev/null 2>&1; then
        ejecutar dpkg -r picoclaw
    fi
    if id picoclaw >/dev/null 2>&1 && confirmar "¿Borrar también su configuración y secretos ($HOME_PC)?" s; then
        ejecutar userdel -r picoclaw 2>/dev/null || ejecutar rm -rf "$(r "$HOME_PC")"
    fi
    guardar_config PICOCLAW no
    ok "PicoClaw desinstalado"
}

case "$ACCION" in
    instalar) instalar ;;
    endurecer) endurecer ;;
    desinstalar) desinstalar ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
