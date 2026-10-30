#!/usr/bin/env bats
# Pruebas del instalador sobre un sistema simulado.

load helpers

setup() { preparar; }
teardown() { limpiar; }

@test "instala sin bloqueador y deja la configuración básica" {
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    grep -qx 'net.ipv4.ip_forward = 1' "$RAIZ/etc/sysctl.d/99-exitnode.conf"
    grep -qx 'net.ipv6.conf.all.forwarding = 1' "$RAIZ/etc/sysctl.d/99-exitnode.conf"
    grep -q 'signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg' "$RAIZ/etc/apt/sources.list.d/tailscale.list"
    grep -q 'https://pkgs.tailscale.com/stable/debian bookworm main' "$RAIZ/etc/apt/sources.list.d/tailscale.list"
    grep -q 'site=pkgs.tailscale.com' "$RAIZ/etc/apt/apt.conf.d/52exitnode-tailscale"
    grep -q 'ethtool -K eth0 rx-udp-gro-forwarding on' "$RAIZ/etc/systemd/system/exitnode-gro.service"
    grep -qx 'BLOQUEADOR="ninguno"' "$RAIZ/etc/exitnode/exitnode.conf"
    [ -x "$RAIZ/usr/local/lib/exitnode/scripts/status.sh" ]
}

@test "el cortafuegos cierra la entrada y solo permite SSH desde casa y Tailscale" {
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    llamado "ufw default deny incoming"
    llamado "ufw default deny routed"
    llamado "ufw route allow in on tailscale0 out on eth0"
    llamado "ufw allow from 192.168.1.0/24 to any port 22 proto tcp"
    llamado "ufw allow 41641/udp"
    llamado "ufw --force enable"
    # El panel web y el DNS no se abren a la red local sin bloqueador.
    nunca grep -q 'ufw allow .*8080' "$REGISTRO"
    nunca grep -q 'port 53' "$REGISTRO"
}

@test "--sin-firewall no toca ufw" {
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno --sin-firewall
    [ "$status" -eq 0 ]
    nunca grep -q '^ufw ' "$REGISTRO"
}

@test "se detiene si la clave de Tailscale no tiene la huella esperada" {
    FALSA_HUELLA=0000000000000000000000000000000000000000 run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -ne 0 ]
    [[ "$output" == *"no tiene la huella esperada"* ]]
    [ ! -f "$RAIZ/usr/share/keyrings/tailscale-archive-keyring.gpg" ]
    nunca llamado "apt-get install -y -q tailscale"
}

@test "rechaza opciones y bloqueadores desconocidos" {
    run bash "$REPO/scripts/install.sh" --bloqueador=dnsmasq
    [ "$status" -ne 0 ]
    run bash "$REPO/scripts/install.sh" --otra-cosa
    [ "$status" -ne 0 ]
}

@test "migra la instalación antigua: para PicoClaw con usuario privilegiado y quita el cron sin verificar" {
    printf '[Service]\nUser=ricardo\nExecStart=/usr/bin/picoclaw gateway\n' >"$RAIZ/etc/systemd/system/picoclaw.service"
    printf '0 4 * * * /bin/bash /home/ricardo/tailscale-exit-node-arm64/scripts/auto_update.sh\n15 3 * * * /usr/bin/otra-tarea\n' >"$RAIZ/crontab"
    FALSO_CRONTAB="$RAIZ/crontab" SUDO_USER=ricardo run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    llamado "systemctl disable --now picoclaw.service"
    nunca grep -q auto_update "$REGISTRO.crontab"
    grep -q otra-tarea "$REGISTRO.crontab"
}

@test "quita el sysctl antiguo solo si no tiene otras líneas" {
    printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' >"$RAIZ/etc/sysctl.d/99-tailscale.conf"
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ ! -f "$RAIZ/etc/sysctl.d/99-tailscale.conf" ]

    printf 'net.ipv4.ip_forward = 1\nvm.swappiness = 10\n' >"$RAIZ/etc/sysctl.d/99-tailscale.conf"
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ -f "$RAIZ/etc/sysctl.d/99-tailscale.conf" ]
}

@test "es idempotente: ejecutarlo dos veces deja el mismo resultado" {
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    cp "$RAIZ/etc/exitnode/exitnode.conf" "$RAIZ/conf1"
    run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    diff "$RAIZ/conf1" "$RAIZ/etc/exitnode/exitnode.conf"
    [ "$(grep -c '^BLOQUEADOR=' "$RAIZ/etc/exitnode/exitnode.conf")" -eq 1 ]
}

@test "con el cron antiguo como única tarea, la instalación no se corta" {
    printf '0 4 * * * /bin/bash /home/ricardo/tailscale-exit-node-arm64/scripts/auto_update.sh\n' >"$RAIZ/crontab"
    FALSO_CRONTAB="$RAIZ/crontab" SUDO_USER=ricardo run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    [[ "$output" == *"Eliminada la tarea cron antigua"* ]]
    [[ "$output" == *"Listo"* ]]
    nunca grep -q auto_update "$REGISTRO.crontab"
}

@test "el cortafuegos siempre deja entrar por SSH al equipo desde el que se instala" {
    SSH_CONNECTION="10.8.0.5 50000 192.168.1.50 22" run bash "$REPO/scripts/install.sh" --bloqueador=ninguno
    [ "$status" -eq 0 ]
    llamado "ufw allow from 10.8.0.5 to any port 22 proto tcp"
    llamado "ufw allow from fe80::/10 to any port 22 proto tcp"
}

@test "--simular no cambia nada, tampoco en el bloqueador que lanza" {
    run bash "$REPO/scripts/install.sh" --simular --bloqueador=adguard
    [ "$status" -eq 0 ]
    nunca grep -qE '^(apt-get|systemctl|curl|useradd) |^ufw (allow|enable|default|route|delete|--force)' "$REGISTRO"
    [[ "$output" == *"[simulado] descarga y comprobación"* ]]
    [ ! -f "$RAIZ/etc/sysctl.d/99-exitnode.conf" ]
}
