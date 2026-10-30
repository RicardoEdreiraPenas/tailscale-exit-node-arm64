#!/usr/bin/env bash
# Actualiza todo a mano (además de las actualizaciones automáticas diarias).
#
# Uso:
#   git pull                       # trae las versiones nuevas fijadas en versiones.conf
#   sudo bash scripts/update.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"
for arg in "$@"; do [[ "$arg" == "--simular" ]] && SIMULAR=1; done
requiere_root
cargar_versiones
leer_config

titulo "Sistema y Tailscale"
ejecutar apt-get update -q
ejecutar env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q
ok "Paquetes al día ($(tailscale version 2>/dev/null | head -1))"

case "$BLOQUEADOR" in
    adguard)
        actual="$(/opt/AdGuardHome/AdGuardHome --version 2>/dev/null | grep -oE 'v[0-9]+(\.[0-9]+)+' | head -1)"
        if [[ "$actual" != "$ADGUARD_VERSION" ]]; then
            info "AdGuard Home $actual -> $ADGUARD_VERSION"
            bash "$DIR_REPO/scripts/bloqueador.sh" instalar adguard
        else
            ok "AdGuard Home $actual ya es la versión fijada"
        fi ;;
    pihole)
        titulo "Pi-hole"
        ejecutar pihole -up ;;
esac

if [[ "${PICOCLAW:-no}" == "si" ]]; then
    actual="$(dpkg-query -W -f='${Version}' picoclaw 2>/dev/null || true)"
    if [[ "v${actual#v}" != "$PICOCLAW_VERSION" ]]; then
        info "PicoClaw ${actual:-?} -> $PICOCLAW_VERSION"
        bash "$DIR_REPO/scripts/picoclaw.sh" actualizar
    else
        ok "PicoClaw $PICOCLAW_VERSION ya es la versión fijada"
    fi
fi

# Copia los scripts de comprobación a su sitio por si han cambiado en el repositorio.
for f in alertas.sh status.sh; do
    ejecutar install -m 0755 "$DIR_REPO/scripts/$f" "$(r /usr/local/lib/exitnode/scripts/$f)"
done
ejecutar install -m 0644 "$DIR_REPO/scripts/lib/comun.sh" "$(r /usr/local/lib/exitnode/scripts/lib/comun.sh)"

bash "$DIR_REPO/scripts/status.sh" || true
