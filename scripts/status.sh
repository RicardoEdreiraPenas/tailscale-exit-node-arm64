#!/usr/bin/env bash
# Panel de estado del exit node.
#
# Uso:
#   sudo bash scripts/status.sh          panel completo (con sudo se ven todos los datos)
#   status.sh --texto                    lo mismo en texto plano (lo usa el asistente de Telegram)
#
# Devuelve 1 si alguna comprobación importante falla, para poder usarlo en scripts.

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"
set +o errexit   # el panel sigue aunque falle una comprobación

if [[ "${1:-}" == "--texto" ]]; then _V='' _R='' _A='' _N='' _X=''; fi
FALLOS=0
mal() { local IFS=' '; error "$*"; FALLOS=$((FALLOS + 1)); }
es_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

leer_config
echo "Informe del exit node: $(hostname), $(date '+%d/%m/%Y %H:%M:%S')"

titulo "Reenvío de paquetes"
if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]]; then ok "IPv4 forwarding activo"; else mal "IPv4 forwarding inactivo"; fi
if [[ "$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)" == "1" ]]; then ok "IPv6 forwarding activo"; else mal "IPv6 forwarding inactivo"; fi

titulo "Tailscale"
if servicio_activo tailscaled; then
    ok "Servicio tailscaled activo ($(tailscale version 2>/dev/null | head -1))"
    if ST="$(tailscale status --json 2>/dev/null)"; then
        if [[ "$(jq -r '.BackendState' <<<"$ST")" == "Running" ]]; then
            ok "Conectado como $(jq -r '.Self.HostName' <<<"$ST") ($(jq -r '.Self.TailscaleIPs[0]' <<<"$ST"))"
        else
            mal "No conectado (estado: $(jq -r '.BackendState' <<<"$ST")). Ejecuta: sudo tailscale up --advertise-exit-node"
        fi
        if es_root && tailscale debug prefs 2>/dev/null | jq -e '.AdvertiseRoutes // [] | index("0.0.0.0/0")' >/dev/null; then
            ok "Se anuncia como exit node"
        elif es_root; then
            mal "No se anuncia como exit node. Ejecuta: sudo tailscale up --advertise-exit-node"
        fi
        # Aprobado = Tailscale le ha concedido la ruta 0.0.0.0/0 (más fiable que ExitNodeOption).
        if jq -e '.Self.AllowedIPs // [] | index("0.0.0.0/0")' <<<"$ST" >/dev/null 2>&1 || \
           [[ "$(jq -r '.Self.ExitNodeOption' <<<"$ST")" == "true" ]]; then
            ok "Aprobado como exit node en el panel de Tailscale"
        else
            aviso "Aún no aprobado como exit node: login.tailscale.com/admin/machines -> Edit route settings"
        fi
        CAD="$(jq -r '.Self.KeyExpiry // empty' <<<"$ST")"
        [[ -n "$CAD" ]] && info "La clave de la máquina caduca el ${CAD%%T*} (Tailscale avisará antes)"
    fi
else
    mal "Servicio tailscaled parado"
fi

titulo "Rendimiento"
if [[ -n "${WAN_IF:-}" ]] && command -v ethtool >/dev/null 2>&1; then
    if ethtool -k "$WAN_IF" 2>/dev/null | grep -q '^rx-udp-gro-forwarding: on'; then
        ok "UDP GRO forwarding activo en $WAN_IF"
    else
        aviso "UDP GRO forwarding no activo en $WAN_IF (necesita kernel 6.2+; el exit node funciona igual, algo más lento)"
    fi
fi
if es_root && command -v tailscale >/dev/null 2>&1; then
    DIRECTAS="$(tailscale status 2>/dev/null | grep -c 'direct' || true)"
    RELES="$(tailscale status 2>/dev/null | grep -c 'relay' || true)"
    info "Conexiones activas: ${DIRECTAS:-0} directas, ${RELES:-0} por relé (los relés son más lentos)"
fi

titulo "Seguridad"
if es_root; then
    if ufw status 2>/dev/null | grep -q '^Status: active'; then ok "Cortafuegos activo"; else mal "Cortafuegos desactivado"; fi
    PA="$(sshd -T 2>/dev/null | awk '/^passwordauthentication/ {print $2}')"
    if [[ "$PA" == "no" ]]; then ok "SSH solo con clave"; else aviso "SSH acepta contraseñas: sudo bash scripts/endurecer_ssh.sh"; fi
else
    info "Ejecuta con sudo para ver cortafuegos y SSH"
fi
if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then ok "Actualizaciones automáticas activas"; else aviso "Actualizaciones automáticas desactivadas"; fi

titulo "Bloqueador de anuncios"
case "$BLOQUEADOR" in
    adguard|pihole)
        SVC=adguardhome; [[ "$BLOQUEADOR" == pihole ]] && SVC=pihole-FTL
        if servicio_activo "$SVC"; then
            ok "$BLOQUEADOR activo"
            R1="$(dig +short +time=2 +tries=1 @127.0.0.1 example.com A 2>/dev/null | head -1)"
            R2="$(dig +short +time=2 +tries=1 @127.0.0.1 doubleclick.net A 2>/dev/null | head -1)"
            if [[ -n "$R1" && "$R1" != "0.0.0.0" ]]; then ok "Resuelve dominios normales"; else mal "No resuelve dominios normales"; fi
            if [[ -z "$R2" || "$R2" == "0.0.0.0" ]]; then ok "Bloquea dominios de anuncios"; else aviso "No ha bloqueado doubleclick.net"; fi
        else
            mal "$BLOQUEADOR instalado pero parado: sudo systemctl status $SVC"
        fi ;;
    *) info "Sin bloqueador (opcional: sudo bash scripts/bloqueador.sh instalar adguard)" ;;
esac

if [[ "${PICOCLAW:-no}" == "si" ]]; then
    titulo "Asistente PicoClaw"
    if servicio_activo picoclaw; then ok "Activo"; else aviso "Parado"; fi
fi

titulo "Sistema"
ok "Encendido: $(uptime -p 2>/dev/null)"
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    T=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
    if (( T > 80 )); then mal "Temperatura de la CPU: ${T} °C"; else ok "Temperatura de la CPU: ${T} °C"; fi
fi
ok "Memoria: $(free -h | awk '/^Mem:/ {print $3" usados de "$2}')"
D="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
if (( D > 90 )); then mal "Disco al ${D}%"; else ok "Disco al ${D}%"; fi
if command -v vnstat >/dev/null 2>&1 && [[ -n "${WAN_IF:-}" ]]; then
    ok "Tráfico de este mes: $(vnstat -i "$WAN_IF" --oneline 2>/dev/null | awk -F';' '{print $9" recibidos, "$10" enviados"}')"
fi

echo
if (( FALLOS > 0 )); then
    printf '%s\n\n' "${_R}$FALLOS comprobaciones con problemas.${_X}"
    exit 1
fi
printf '%s\n\n' "${_V}Todo correcto.${_X}"
