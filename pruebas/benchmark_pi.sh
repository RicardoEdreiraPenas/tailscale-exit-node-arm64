#!/usr/bin/env bash
# Mide en la Raspberry real lo que no se puede medir en un laboratorio:
# latencia DNS con y sin bloqueador, si bloquea, calidad de la conexión de Tailscale
# y, opcionalmente, deja un servidor iperf3 para medir el caudal del exit node.
#
# Uso (en la Raspberry):
#   sudo bash pruebas/benchmark_pi.sh            # DNS, bloqueo, Tailscale y sistema
#   sudo bash pruebas/benchmark_pi.sh --iperf    # además, servidor iperf3 durante 5 minutos
#
# El caudal real del exit node se mide desde otro dispositivo con
# pruebas/velocidad_cliente.sh (Mac o Linux).

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/comun.sh"
set +o errexit
requiere_root
leer_config
requiere_comando dig jq

MUESTRAS=40
NORMALES=(google.com youtube.com wikipedia.org elpais.com netflix.com amazon.es github.com bbva.es renfe.com boe.es)
ANUNCIOS=(doubleclick.net googleadservices.com googlesyndication.com adservice.google.com ads.youtube.com
          pagead2.googlesyndication.com analytics.google.com connect.facebook.net ads.tiktok.com app-measurement.com)

# Mediana y percentil 95 de la columna "Query time" de dig, en ms.
medir() {
    local servidor="$1"; shift
    local t
    for d in "$@"; do
        t="$(dig +tries=1 +time=3 @"$servidor" "$d" A | awk '/Query time/ {print $4}')"
        echo "${t:-3000}"
    done | sort -n | awk '{a[NR]=$1} END {printf "mediana %s ms, p95 %s ms (%d consultas)", a[int(NR*0.5)+1], a[int(NR*0.95)+1], NR}'
}

aleatorios() {
    local n="$1" i
    for ((i = 0; i < n; i++)); do printf 'x%s.%s\n' "$RANDOM$RANDOM" "${NORMALES[$((i % ${#NORMALES[@]}))]}"; done
}

titulo "Sistema"
info "Placa: $(tr -d '\0' </proc/device-tree/model 2>/dev/null || uname -m), kernel $(uname -r)"
info "Carga: $(cut -d' ' -f1-3 /proc/loadavg), temperatura: $(( $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0) / 1000 )) °C"
if [[ -n "${WAN_IF:-}" ]]; then
    info "GRO forwarding en $WAN_IF: $(ethtool -k "$WAN_IF" 2>/dev/null | awk -F': ' '/^rx-udp-gro-forwarding/ {print $2}')"
fi

titulo "DNS sin bloqueador (directo a Quad9)"
mapfile -t NUEVOS < <(aleatorios "$MUESTRAS")
info "Consultas nuevas: $(medir 9.9.9.9 "${NUEVOS[@]}")"
mapfile -t REPES < <(for _ in 1 2 3 4; do printf '%s\n' "${NORMALES[@]}"; done)
info "Dominios habituales: $(medir 9.9.9.9 "${REPES[@]}")"

if [[ "$BLOQUEADOR" == "adguard" || "$BLOQUEADOR" == "pihole" ]]; then
    titulo "DNS con $BLOQUEADOR (127.0.0.1)"
    mapfile -t NUEVOS < <(aleatorios "$MUESTRAS")
    info "Consultas nuevas: $(medir 127.0.0.1 "${NUEVOS[@]}")"
    medir 127.0.0.1 "${NORMALES[@]}" >/dev/null   # llena la caché
    info "Dominios habituales (en caché): $(medir 127.0.0.1 "${REPES[@]}")"
    info "Dominios bloqueados: $(medir 127.0.0.1 "${ANUNCIOS[@]}")"

    titulo "Eficacia"
    bloq=0
    for d in "${ANUNCIOS[@]}"; do
        r="$(dig +short +time=2 +tries=1 @127.0.0.1 "$d" A | head -1)"
        if [[ -z "$r" || "$r" == "0.0.0.0" ]]; then bloq=$((bloq + 1)); else aviso "No bloqueado: $d"; fi
    done
    info "Anuncios bloqueados: $bloq/${#ANUNCIOS[@]}"
    malos=0
    for d in "${NORMALES[@]}"; do
        r="$(dig +short +time=2 +tries=1 @127.0.0.1 "$d" A | head -1)"
        if [[ -z "$r" || "$r" == "0.0.0.0" ]]; then malos=$((malos + 1)); aviso "Bloqueado por error: $d"; fi
    done
    info "Webs normales bloqueadas por error: $malos/${#NORMALES[@]}"
    SVC=adguardhome; [[ "$BLOQUEADOR" == pihole ]] && SVC=pihole-FTL
    PID="$(systemctl show -p MainPID --value "$SVC")"
    [[ "$PID" -gt 0 ]] && info "Memoria del bloqueador: $(( $(awk '/VmRSS/ {print $2}' "/proc/$PID/status") / 1024 )) MB"
else
    info "Sin bloqueador instalado: se omite la comparación."
fi

titulo "Tailscale"
tailscale netcheck 2>/dev/null | grep -E 'UDP|IPv4|Nearest DERP|DERP latency' | head -6 | sed 's/^/  /'
info "Conexiones: $(tailscale status 2>/dev/null | grep -c direct) directas, $(tailscale status 2>/dev/null | grep -c relay) por relé"

if [[ " $* " == *" --iperf "* ]]; then
    titulo "Servidor iperf3 (5 minutos)"
    command -v iperf3 >/dev/null || ejecutar env DEBIAN_FRONTEND=noninteractive apt-get install -y -q iperf3 >/dev/null
    IP_TS="$(tailscale ip -4 | head -1)"
    info "Desde otro dispositivo con Tailscale ejecuta:"
    info "  bash pruebas/velocidad_cliente.sh $(hostname) $IP_TS"
    timeout 300 iperf3 -s -B "$IP_TS" || true
fi
echo
