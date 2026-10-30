#!/usr/bin/env bash
# Instalación del exit node de Tailscale en una Raspberry Pi (ARM64).
#
# Uso:
#   sudo bash scripts/install.sh [opciones]
#
# Opciones:
#   --bloqueador=adguard|pihole|ninguno   bloqueador de anuncios por DNS (por defecto se pregunta)
#   --con-picoclaw                        instala también el asistente de Telegram (opcional)
#   --sin-firewall                        no configura el cortafuegos (no recomendado)
#   --simular                             muestra lo que haría sin cambiar nada
#   -s, --si                              no pregunta; usa las opciones indicadas

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"

BLOQUEADOR_ELEGIDO=""
CON_PICOCLAW=0
CON_FIREWALL=1

for arg in "$@"; do
    case "$arg" in
        --bloqueador=*) BLOQUEADOR_ELEGIDO="${arg#*=}" ;;
        --con-picoclaw) CON_PICOCLAW=1 ;;
        --sin-firewall) CON_FIREWALL=0 ;;
        --simular)      SIMULAR=1 ;;
        -s|--si)        NO_INTERACTIVO=1 ;;
        -h|--help)      sed -n '2,15p' "$0"; exit 0 ;;
        *) morir "Opción desconocida: $arg (usa --help)" ;;
    esac
done

case "$BLOQUEADOR_ELEGIDO" in
    ""|adguard|pihole|ninguno) ;;
    *) morir "Bloqueador no válido: $BLOQUEADOR_ELEGIDO. Usa adguard, pihole o ninguno." ;;
esac

requiere_root
cargar_versiones

# ---------------------------------------------------------------------------
comprobaciones_previas() {
    titulo "Comprobaciones previas"
    [[ -f "$(r /etc/debian_version)" ]] || morir "Este instalador es para Raspberry Pi OS o Debian."
    ARQ="$(arquitectura)"
    if [[ "$ARQ" != "arm64" ]]; then
        aviso "Arquitectura $ARQ: el proyecto está pensado para ARM64. Sigo, pero no es la configuración probada."
    fi
    # shellcheck source=/dev/null
    source "$(r /etc/os-release)"
    CODENAME="${VERSION_CODENAME:-}"
    [[ -n "$CODENAME" ]] || morir "No se pudo saber la versión de Debian (VERSION_CODENAME)."
    DISTRO_TS="debian"
    [[ "${ID:-}" == "ubuntu" ]] && DISTRO_TS="ubuntu"

    WAN_IF="$(interfaz_salida)"
    [[ -n "$WAN_IF" ]] || morir "No hay ruta por defecto. Conecta la placa a la red antes de instalar."
    LAN_SUBRED="$(subred_lan "$WAN_IF")"
    ok "Sistema: ${PRETTY_NAME:-Debian} ($CODENAME), interfaz de salida $WAN_IF, red local ${LAN_SUBRED:-desconocida}"
}

instalar_dependencias() {
    titulo "Paquetes del sistema"
    ejecutar apt-get update -q
    ejecutar env DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        curl ca-certificates gnupg ethtool jq iproute2 dnsutils ufw unattended-upgrades apt-listchanges
    ok "Dependencias instaladas"
}

configurar_reenvio() {
    titulo "Reenvío de paquetes (necesario para el exit node)"
    escribir_fichero /etc/sysctl.d/99-exitnode.conf 0644 <<'EOF'
# Necesario para que la placa reenvíe el tráfico de los dispositivos que la usan como exit node.
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    # Versiones anteriores del proyecto usaban otro nombre de fichero.
    if [[ -f "$(r /etc/sysctl.d/99-tailscale.conf)" ]] && \
       ! grep -qvE '^(net\.ipv4\.ip_forward|net\.ipv6\.conf\.all\.forwarding) = 1$|^$' "$(r /etc/sysctl.d/99-tailscale.conf)"; then
        ejecutar rm -f "$(r /etc/sysctl.d/99-tailscale.conf)"
    fi
    ejecutar sysctl -q -p "$(r /etc/sysctl.d/99-exitnode.conf)"
    ok "IPv4 e IPv6 forwarding activos"
}

instalar_tailscale() {
    titulo "Tailscale desde su repositorio oficial firmado"
    local llavero tmp huella
    llavero="/usr/share/keyrings/tailscale-archive-keyring.gpg"
    tmp="$(mktemp)"
    if [[ "$SIMULAR" != "1" ]]; then
        curl --fail --silent --show-error --proto '=https' --tlsv1.2 -o "$tmp" \
            "https://pkgs.tailscale.com/stable/${DISTRO_TS}/${CODENAME}.noarmor.gpg" \
            || morir "No se pudo descargar la clave de Tailscale."
        huella="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '$1=="fpr" {print $10; exit}')"
        [[ "$huella" == "$TAILSCALE_GPG_FINGERPRINT" ]] \
            || { rm -f "$tmp"; morir "La clave de Tailscale no tiene la huella esperada ($huella). No continúo."; }
        install -m 0644 "$tmp" "$(r "$llavero")"
        ok "Clave de Tailscale verificada ($huella)"
    fi
    rm -f "$tmp"
    escribir_fichero /etc/apt/sources.list.d/tailscale.list 0644 <<EOF
deb [signed-by=${llavero}] https://pkgs.tailscale.com/stable/${DISTRO_TS} ${CODENAME} main
EOF
    ejecutar apt-get update -q
    ejecutar env DEBIAN_FRONTEND=noninteractive apt-get install -y -q tailscale
    ejecutar systemctl enable --now tailscaled
    ok "Tailscale instalado y activo"
}

optimizar_rendimiento() {
    titulo "Rendimiento del exit node"
    # Tailscale recomienda activar UDP GRO forwarding en la interfaz de salida (kernel 6.2 o superior).
    # Reduce el uso de CPU y mejora el caudal cuando la placa reenvía tráfico.
    sed "s|@WAN_IF@|${WAN_IF}|g" "$DIR_REPO/config/systemd/exitnode-gro.service" \
        | escribir_fichero /etc/systemd/system/exitnode-gro.service 0644
    ejecutar systemctl daemon-reload
    ejecutar systemctl enable --now exitnode-gro.service
    ok "UDP GRO forwarding configurado en $WAN_IF"
}

actualizaciones_automaticas() {
    titulo "Actualizaciones de seguridad automáticas"
    escribir_fichero /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    escribir_fichero /etc/apt/apt.conf.d/52exitnode-tailscale 0644 <<'EOF'
// Incluye Tailscale en las actualizaciones automáticas, además de las de seguridad del sistema.
Unattended-Upgrade::Origins-Pattern {
    "site=pkgs.tailscale.com";
};
EOF
    ok "Sistema y Tailscale se actualizan solos cada día (unattended-upgrades)"
}

configurar_firewall() {
    titulo "Cortafuegos (ufw)"
    if [[ "$CON_FIREWALL" != "1" ]]; then
        aviso "Cortafuegos omitido por --sin-firewall."
        return 0
    fi
    [[ -n "$LAN_SUBRED" ]] || morir "No se pudo detectar la red local; no activo el cortafuegos para no dejarte sin SSH. Usa --sin-firewall y configúralo a mano."
    ejecutar ufw --force reset >/dev/null
    ejecutar ufw default deny incoming
    ejecutar ufw default allow outgoing
    ejecutar ufw default deny routed
    # Tráfico de Tailscale: conexiones directas (más rápidas que los relés) y la propia red privada.
    ejecutar ufw allow 41641/udp comment 'Tailscale: conexiones directas'
    ejecutar ufw allow in on tailscale0 comment 'Tailscale: red privada'
    # El exit node: lo que entra por Tailscale puede salir a internet.
    ejecutar ufw route allow in on tailscale0 out on "$WAN_IF" comment 'Exit node'
    # SSH desde casa (IPv4 y direcciones IPv6 de enlace local, que usa raspberrypi.local en macOS)
    # y por Tailscale, ya permitido arriba.
    ejecutar ufw allow from "$LAN_SUBRED" to any port 22 proto tcp comment 'SSH desde la red local'
    ejecutar ufw allow from fe80::/10 to any port 22 proto tcp comment 'SSH desde la red local (IPv6)'
    # Y siempre desde el equipo desde el que estás conectado ahora, esté en la subred que esté.
    local cliente="${SSH_CONNECTION:-}"
    cliente="${cliente%% *}"
    if [[ -n "${SSH_CONNECTION:-}" && "$cliente" =~ ^[0-9a-fA-F:.]+$ ]]; then
        cliente="${cliente%%%*}"
        ejecutar ufw allow from "$cliente" to any port 22 proto tcp comment 'SSH desde el equipo de la instalación'
    fi
    armar_vuelta_atras
    ejecutar ufw --force enable
    ok "Cortafuegos activo: entrada cerrada salvo SSH desde $LAN_SUBRED, ${cliente:-tu equipo} y la red de Tailscale"
    confirmar_acceso_ssh
}

# Si al activar el cortafuegos te quedas sin SSH, lo desactiva solo a los 10 minutos.
armar_vuelta_atras() {
    [[ -n "${SSH_CONNECTION:-}" && -t 0 && "$NO_INTERACTIVO" != "1" ]] || return 0
    ejecutar systemd-run --quiet --unit=exitnode-ufw-vuelta-atras --on-active=10min /usr/sbin/ufw --force disable \
        || aviso "No se pudo programar la vuelta atrás del cortafuegos."
    VUELTA_ATRAS=1
}

confirmar_acceso_ssh() {
    [[ "${VUELTA_ATRAS:-0}" == "1" ]] || return 0
    printf '\n  %s\n  %s\n\n' \
        "Comprobación de seguridad: abre OTRA terminal y conéctate por SSH a la placa." \
        "Si no pudieras entrar, no hagas nada: el cortafuegos se desactivará solo en 10 minutos."
    if confirmar "¿Has podido entrar por SSH desde otra terminal?" n; then
        ejecutar systemctl stop exitnode-ufw-vuelta-atras.timer 2>/dev/null || true
        ok "Cortafuegos confirmado"
    else
        aviso "El cortafuegos se desactivará en 10 minutos. Revisa la regla de SSH y vuelve a ejecutar el instalador."
    fi
}

migrar_instalacion_antigua() {
    titulo "Restos de versiones anteriores"
    local u
    # El servicio antiguo de PicoClaw corría con el usuario principal; lo paro hasta reconfigurarlo.
    if [[ -f "$(r /etc/systemd/system/picoclaw.service)" ]] && \
       grep -qE '^User=' "$(r /etc/systemd/system/picoclaw.service)" && \
       ! grep -q '^User=picoclaw$' "$(r /etc/systemd/system/picoclaw.service)"; then
        aviso "El servicio picoclaw antiguo corre con un usuario con privilegios. Lo detengo y desactivo."
        ejecutar systemctl disable --now picoclaw.service || true
        info "Para volver a usarlo de forma segura: sudo bash scripts/picoclaw.sh instalar"
    fi
    # La tarea cron antigua de auto_update.sh instalaba paquetes sin verificar como root.
    for u in root "${SUDO_USER:-}"; do
        [[ -n "$u" ]] || continue
        local actual
        actual="$(crontab -u "$u" -l 2>/dev/null || true)"
        if grep -q 'auto_update.sh' <<<"$actual"; then
            # grep -v devuelve 1 si no queda ninguna línea: no debe cortar la instalación.
            { grep -v 'auto_update.sh' <<<"$actual" || true; } | ejecutar crontab -u "$u" -
            ok "Eliminada la tarea cron antigua de auto_update.sh ($u)"
        fi
    done
    ok "Revisión completada"
}

instalar_alertas() {
    titulo "Comprobaciones periódicas y alertas por Telegram"
    # Copia de los scripts que usan los servicios, fuera del repositorio clonado
    # (así funcionan aunque muevas o borres la carpeta del repositorio).
    local d=/usr/local/lib/exitnode
    ejecutar install -d -m 0755 "$(r "$d/scripts/lib")"
    ejecutar install -m 0755 "$DIR_REPO/scripts/alertas.sh" "$(r "$d/scripts/alertas.sh")"
    ejecutar install -m 0755 "$DIR_REPO/scripts/status.sh" "$(r "$d/scripts/status.sh")"
    ejecutar install -m 0644 "$DIR_REPO/scripts/lib/comun.sh" "$(r "$d/scripts/lib/comun.sh")"
    ejecutar install -m 0644 "$DIR_REPO/versiones.conf" "$(r "$d/versiones.conf")"
    escribir_fichero /etc/systemd/system/exitnode-alertas.service 0644 <"$DIR_REPO/config/systemd/exitnode-alertas.service"
    escribir_fichero /etc/systemd/system/exitnode-alertas.timer 0644 <"$DIR_REPO/config/systemd/exitnode-alertas.timer"
    ejecutar systemctl daemon-reload
    if [[ -s "$(r "$DIR_CONF/alertas.env")" ]]; then
        ejecutar systemctl enable --now exitnode-alertas.timer
        ok "Alertas activas"
    else
        info "Para activarlas: sudo bash scripts/alertas.sh --configurar"
    fi
}

resumen_final() {
    titulo "Listo"
    cat <<EOF

  Siguientes pasos:

  1. Conecta la placa a tu red de Tailscale y anúnciala como exit node:
       sudo tailscale up --advertise-exit-node

  2. En https://login.tailscale.com/admin/machines abre esta máquina:
       - "Edit route settings" -> marca "Use as exit node".

  3. Comprueba que todo está bien:
       sudo bash scripts/status.sh

  Recomendado: inicia sesión por SSH con clave y desactiva las contraseñas:
       sudo bash scripts/endurecer_ssh.sh

EOF
}

comprobaciones_previas
instalar_dependencias
migrar_instalacion_antigua
configurar_reenvio
instalar_tailscale
optimizar_rendimiento
actualizaciones_automaticas

if [[ -z "$BLOQUEADOR_ELEGIDO" ]]; then
    if confirmar "¿Quieres instalar un bloqueador de anuncios (AdGuard Home)? Si prefieres Pi-hole, usa --bloqueador=pihole" n; then
        BLOQUEADOR_ELEGIDO="adguard"
    else
        BLOQUEADOR_ELEGIDO="ninguno"
    fi
fi
guardar_config BLOQUEADOR "$BLOQUEADOR_ELEGIDO"
guardar_config WAN_IF "$WAN_IF"
guardar_config LAN_SUBRED "${LAN_SUBRED:-}"

configurar_firewall
if [[ "$BLOQUEADOR_ELEGIDO" != "ninguno" ]]; then
    bash "$DIR_REPO/scripts/bloqueador.sh" instalar "$BLOQUEADOR_ELEGIDO"
fi
instalar_alertas
if [[ "$CON_PICOCLAW" == "1" ]]; then
    bash "$DIR_REPO/scripts/picoclaw.sh" instalar
fi
resumen_final
