#!/usr/bin/env bash
# Bloqueador de anuncios por DNS: AdGuard Home o Pi-hole (solo uno a la vez).
#
# Uso:
#   sudo bash scripts/bloqueador.sh instalar adguard|pihole
#   sudo bash scripts/bloqueador.sh desinstalar
#   sudo bash scripts/bloqueador.sh probar
#
# Los dos escuchan en el puerto 53, por eso no pueden convivir.
# El panel web queda en el puerto 8080 y el cortafuegos solo lo abre por Tailscale.

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"

ACCION="${1:-}"
TIPO="${2:-}"
[[ " ${*} " == *" --simular "* ]] && SIMULAR=1

requiere_root
cargar_versiones
leer_config

AG_DIR=/opt/AdGuardHome
AG_DATOS=/var/lib/adguardhome

adguard_instalado() { [[ -x "$(r "$AG_DIR/AdGuardHome")" ]]; }
pihole_instalado()  { [[ -x "$(r /usr/local/bin/pihole)" || -f "$(r /etc/pihole/pihole.toml)" ]]; }

pedir_contrasena() {
    # Devuelve una contraseña escrita por el usuario o una aleatoria si no hay terminal.
    local p1 p2
    if [[ "$NO_INTERACTIVO" == "1" || ! -t 0 ]]; then
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
        return
    fi
    while true; do
        read -r -s -p "  Contraseña para el panel web (mínimo 12 caracteres, vacío = generar una): " p1; echo >&2
        if [[ -z "$p1" ]]; then
            tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
            return
        fi
        read -r -s -p "  Repítela: " p2; echo >&2
        if [[ "$p1" != "$p2" ]]; then error "No coinciden."; continue; fi
        if (( ${#p1} < 12 )); then error "Demasiado corta."; continue; fi
        printf '%s' "$p1"
        return
    done
}

comprobar_puerto_53_libre() {
    if puerto_ocupado 53; then
        local quien
        quien="$(ss -Hlnup 'sport = :53' 2>/dev/null | grep -o 'users:(("[^"]*' | head -1 | cut -d'"' -f2)"
        morir "El puerto 53 ya lo usa '${quien:-otro programa}'. Desinstálalo antes (sudo bash scripts/bloqueador.sh desinstalar)."
    fi
}

abrir_firewall_dns() {
    command -v ufw >/dev/null 2>&1 || return 0
    ufw status 2>/dev/null | grep -q '^Status: active' || return 0
    if [[ -n "${LAN_SUBRED:-}" ]]; then
        ejecutar ufw allow from "$LAN_SUBRED" to any port 53 comment 'DNS desde la red local'
    fi
    # Desde Tailscale ya está permitido todo lo que entra por tailscale0 (DNS y panel web).
    ok "Cortafuegos: DNS abierto a ${LAN_SUBRED:-la red local} y a Tailscale; panel web solo por Tailscale"
}

cerrar_firewall_dns() {
    command -v ufw >/dev/null 2>&1 || return 0
    if [[ -n "${LAN_SUBRED:-}" ]]; then
        ejecutar ufw delete allow from "$LAN_SUBRED" to any port 53 >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
instalar_adguard() {
    titulo "AdGuard Home $ADGUARD_VERSION"
    pihole_instalado && morir "Pi-hole está instalado. Solo puede haber un bloqueador: desinstálalo primero."
    local arq suma tmp pass hash
    arq="$(arquitectura)"
    if [[ "$arq" == "arm64" ]]; then suma="$ADGUARD_SHA256_ARM64"; else suma="$ADGUARD_SHA256_AMD64"; fi

    if ! adguard_instalado; then
        comprobar_puerto_53_libre
    fi
    ejecutar env DEBIAN_FRONTEND=noninteractive apt-get install -y -q apache2-utils >/dev/null

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    descargar_verificado \
        "https://github.com/AdguardTeam/AdGuardHome/releases/download/${ADGUARD_VERSION}/AdGuardHome_linux_${arq}.tar.gz" \
        "$tmp/adguard.tar.gz" "$suma"
    # Las versiones anteriores del proyecto usaban el servicio del instalador oficial (corre como root).
    # Se para antes de tocar nada para poder migrar su configuración con los datos quietos.
    if [[ -f "$(r /etc/systemd/system/AdGuardHome.service)" ]]; then
        ejecutar systemctl disable --now AdGuardHome.service || true
    fi
    if [[ "$SIMULAR" != "1" ]]; then
        tar -xzf "$tmp/adguard.tar.gz" -C "$tmp"
        install -d -m 0755 "$(r "$AG_DIR")"
        install -m 0755 "$tmp/AdGuardHome/AdGuardHome" "$(r "$AG_DIR/AdGuardHome")"
    fi

    if ! id adguardhome >/dev/null 2>&1; then
        ejecutar useradd --system --home-dir "$AG_DATOS" --no-create-home --shell /usr/sbin/nologin adguardhome
    fi
    ejecutar install -d -m 0750 -o adguardhome -g adguardhome "$(r "$AG_DATOS")"

    if [[ -f "$(r "$AG_DATOS/AdGuardHome.yaml")" ]]; then
        info "Ya hay una configuración en $AG_DATOS: la conservo (solo se actualiza el programa)."
    elif [[ -f "$(r "$AG_DIR/AdGuardHome.yaml")" ]]; then
        # Instalación anterior: se conservan listas, clientes, estadísticas y contraseña.
        ejecutar install -m 0600 -o adguardhome -g adguardhome "$(r "$AG_DIR/AdGuardHome.yaml")" "$(r "$AG_DATOS/AdGuardHome.yaml")"
        if [[ -d "$(r "$AG_DIR/data")" ]]; then
            ejecutar cp -a "$(r "$AG_DIR/data")" "$(r "$AG_DATOS/")"
            ejecutar chown -R adguardhome:adguardhome "$(r "$AG_DATOS/data")"
        fi
        ok "Configuración anterior migrada a $AG_DATOS (la contraseña del panel es la que ya tenías)"
        aviso "El panel queda en el puerto que tuvieras configurado; con el cortafuegos solo es accesible por Tailscale."
    else
        pass="$(pedir_contrasena)"
        if [[ "$SIMULAR" == "1" ]]; then
            # shellcheck disable=SC2016  # es un texto literal, no una expansión
            hash='$2y$10$simulado'
        else
            hash="$(htpasswd -inBC 10 admin <<<"$pass" | cut -d: -f2)"
        fi
        sed -e "s|@ADMIN_USER@|admin|" -e "s|@ADMIN_HASH@|${hash}|" \
            "$DIR_REPO/config/plantillas/AdGuardHome.yaml" \
            | escribir_fichero "$AG_DATOS/AdGuardHome.yaml" 0600 adguardhome:adguardhome
        GUARDAR_PASS="$pass"
    fi

    escribir_fichero /etc/systemd/system/adguardhome.service 0644 <"$DIR_REPO/config/systemd/adguardhome.service"
    ejecutar rm -f "$(r /etc/systemd/system/AdGuardHome.service)"
    ejecutar systemctl daemon-reload
    ejecutar systemctl enable adguardhome.service
    ejecutar systemctl restart adguardhome.service
    guardar_config BLOQUEADOR adguard
    abrir_firewall_dns
    esperar_y_probar
    datos_de_acceso "AdGuard Home" "admin"
}

instalar_pihole() {
    titulo "Pi-hole $PIHOLE_VERSION"
    adguard_instalado && morir "AdGuard Home está instalado. Solo puede haber un bloqueador: desinstálalo primero."
    local tmp pass
    if ! pihole_instalado; then
        comprobar_puerto_53_libre
    fi
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    descargar_verificado \
        "https://raw.githubusercontent.com/pi-hole/pi-hole/${PIHOLE_VERSION}/automated%20install/basic-install.sh" \
        "$tmp/basic-install.sh" "$PIHOLE_INSTALLER_SHA256"

    # Con la configuración ya creada, el instalador oficial no abre diálogos.
    if [[ ! -f "$(r /etc/pihole/pihole.toml)" ]]; then
        escribir_fichero /etc/pihole/pihole.toml 0644 <"$DIR_REPO/config/plantillas/pihole.toml"
    fi
    ejecutar env PIHOLE_SKIP_OS_CHECK=false bash "$tmp/basic-install.sh" --unattended

    if [[ -z "${PIHOLE_PASS_HECHA:-}" ]]; then
        pass="$(pedir_contrasena)"
        if [[ "$SIMULAR" == "1" ]]; then
            printf '  [simulado] pihole setpassword\n'
        else
            pihole setpassword "$pass" >/dev/null
        fi
        GUARDAR_PASS="$pass"
    fi
    guardar_config BLOQUEADOR pihole
    abrir_firewall_dns
    esperar_y_probar
    datos_de_acceso "Pi-hole" ""
}

esperar_y_probar() {
    [[ "$SIMULAR" == "1" ]] && return 0
    for _ in $(seq 1 30); do
        dig +time=1 +tries=1 @127.0.0.1 example.com A >/dev/null 2>&1 && break
        sleep 1
    done
    probar
}

# Comprueba que el bloqueador responde, bloquea un dominio de anuncios y no bloquea uno normal.
probar() {
    titulo "Prueba del bloqueador"
    local bueno malo
    bueno="$(dig +short +time=2 +tries=1 @127.0.0.1 example.com A | head -1)"
    malo="$(dig +short +time=2 +tries=1 @127.0.0.1 doubleclick.net A | head -1)"
    if [[ -z "$bueno" || "$bueno" == "0.0.0.0" ]]; then
        error "No resuelve dominios normales (example.com). Revisa: journalctl -u ${BLOQUEADOR_SERVICIO:-adguardhome}"
        return 1
    fi
    ok "Resuelve dominios normales (example.com -> $bueno)"
    if [[ -z "$malo" || "$malo" == "0.0.0.0" ]]; then
        ok "Bloquea anuncios (doubleclick.net -> ${malo:-sin respuesta})"
    else
        aviso "doubleclick.net no se ha bloqueado ($malo). Puede que las listas aún se estén descargando."
    fi
}

datos_de_acceso() {
    local nombre="$1" usuario="$2" ip_ts
    ip_ts="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    cat <<EOF

  $nombre listo.

  Panel web (solo por Tailscale): http://${ip_ts:-<IP de Tailscale de la placa>}:8080
EOF
    [[ -n "$usuario" ]] && echo "  Usuario: $usuario"
    if [[ -n "${GUARDAR_PASS:-}" ]]; then
        echo "  Contraseña: $GUARDAR_PASS"
        echo "  (Guárdala en tu gestor de contraseñas: no se vuelve a mostrar.)"
    fi
    cat <<EOF

  Para que tus dispositivos lo usen, en https://login.tailscale.com/admin/dns:
    1. "Add nameserver" -> "Custom" -> ${ip_ts:-la IP de Tailscale de la placa}
    2. Activa "Override DNS servers".
  Ojo: si la placa se apaga, los dispositivos conectados a Tailscale se quedan sin DNS
  hasta que la quites de ahí o desactives Tailscale en ese dispositivo.

EOF
}

desinstalar() {
    titulo "Desinstalar el bloqueador"
    if adguard_instalado; then
        ejecutar systemctl disable --now adguardhome.service || true
        ejecutar rm -f "$(r /etc/systemd/system/adguardhome.service)"
        ejecutar rm -rf "$(r "$AG_DIR")"
        if confirmar "¿Borrar también la configuración y estadísticas de AdGuard ($AG_DATOS)?" n; then
            ejecutar rm -rf "$(r "$AG_DATOS")"
            ejecutar userdel adguardhome || true
        fi
        ejecutar systemctl daemon-reload
        ok "AdGuard Home desinstalado"
    fi
    if pihole_instalado; then
        aviso "Pi-hole tiene su propio desinstalador, que pregunta qué paquetes quitar:"
        info "  sudo pihole uninstall"
    fi
    cerrar_firewall_dns
    guardar_config BLOQUEADOR ninguno
}

case "$ACCION" in
    instalar)
        case "$TIPO" in
            adguard) instalar_adguard ;;
            pihole)  instalar_pihole ;;
            *) morir "Indica cuál: sudo bash scripts/bloqueador.sh instalar adguard|pihole" ;;
        esac ;;
    desinstalar) desinstalar ;;
    probar) probar ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
