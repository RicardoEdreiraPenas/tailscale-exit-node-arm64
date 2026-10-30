#!/usr/bin/env bash
# Mide cuánto cambia la velocidad al usar la Raspberry como exit node.
# Se ejecuta en un Mac o en Linux con Tailscale y deja todo como estaba al terminar.
#
# Uso:
#   bash pruebas/velocidad_cliente.sh <nombre-o-IP-de-la-placa> [IP de Tailscale para iperf3]
#
# Mide, sin exit node y con él:
#   - latencia (ping a 1.1.1.1)
#   - descarga y subida (networkQuality en Mac; descarga de prueba de Cloudflare en Linux)
# Y si pasas la IP y en la placa corre 'benchmark_pi.sh --iperf', el caudal del túnel con iperf3.

set -o nounset -o pipefail
PLACA="${1:?Indica el nombre o la IP de Tailscale de la placa}"
IP_IPERF="${2:-}"

if command -v tailscale >/dev/null 2>&1; then TS=tailscale
elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
else echo "No encuentro el comando de Tailscale." >&2; exit 1; fi

ANTERIOR="$("$TS" status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d.get("ExitNodeStatus") or {}; print((s.get("TailscaleIPs") or [""])[0].split("/")[0])' 2>/dev/null)"
restaurar() { "$TS" set --exit-node="${ANTERIOR}" >/dev/null 2>&1; echo; echo "Exit node restaurado a: ${ANTERIOR:-ninguno}"; }
trap restaurar EXIT

latencia() {
    ping -c 10 -q 1.1.1.1 2>/dev/null | awk -F'/' '/^(rtt|round-trip)/ {printf "%.1f ms de media", $5}'
}
velocidad() {
    if command -v networkQuality >/dev/null 2>&1; then
        networkQuality -s 2>/dev/null | awk -F': ' '/Uplink capacity|Downlink capacity|Responsiveness/ {printf "%s: %s | ", $1, $2}'
    else
        curl -s -o /dev/null -w 'Descarga: %{speed_download}\n' 'https://speed.cloudflare.com/__down?bytes=100000000' \
            | awk '{printf "Descarga: %.1f Mbit/s", $2*8/1000000}'
    fi
}
medir() {
    echo "  Latencia: $(latencia)"
    echo "  $(velocidad)"
    echo "  IP pública: $(curl -s --max-time 10 https://ifconfig.me 2>/dev/null)"
}

echo "== Sin exit node"
"$TS" set --exit-node= >/dev/null
sleep 2
medir

echo "== Con la placa ($PLACA) como exit node"
"$TS" set --exit-node="$PLACA" --exit-node-allow-lan-access=true >/dev/null || { echo "No se pudo activar el exit node." >&2; exit 1; }
sleep 4
"$TS" ping -c 3 "$PLACA" 2>/dev/null | tail -1 | sed 's/^/  Tailscale: /'
medir

if [[ -n "$IP_IPERF" ]] && command -v iperf3 >/dev/null 2>&1; then
    echo "== Caudal del túnel hasta la placa (iperf3)"
    "$TS" set --exit-node= >/dev/null
    iperf3 -c "$IP_IPERF" -t 10 2>/dev/null | awk '/receiver/ {print "  Subida hacia la placa: " $7 " " $8}'
    iperf3 -c "$IP_IPERF" -t 10 -R 2>/dev/null | awk '/receiver/ {print "  Bajada desde la placa: " $7 " " $8}'
fi

cat <<'EOF'

Cómo leerlo:
  - Con exit node la velocidad no puede superar la subida de tu fibra de casa, porque todo
    sale por ella. Si la placa es una Raspberry Pi 4 o 5 con GRO activo, el límite suele ser la fibra.
  - Si "Tailscale" dice "via DERP" en lugar de una IP directa, la conexión va por un relé y será
    más lenta: revisa que el cortafuegos permita 41641/udp (lo hace install.sh).
EOF
