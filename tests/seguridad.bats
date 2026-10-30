#!/usr/bin/env bats
# Pruebas de las piezas que protegen el sistema: descargas, secretos y bloqueador.

load helpers

setup() { preparar; }
teardown() { limpiar; }

@test "una descarga con la suma correcta se acepta" {
    echo "paquete legítimo" >"$RAIZ/fuente"
    suma="$(sha256sum "$RAIZ/fuente" | cut -d' ' -f1)"
    FALSA_DESCARGA="$RAIZ/fuente" run bash -c "source '$REPO/scripts/lib/comun.sh'; descargar_verificado https://ejemplo.org/p.deb '$RAIZ/p.deb' $suma"
    [ "$status" -eq 0 ]
    [ -f "$RAIZ/p.deb" ]
}

@test "una descarga manipulada se rechaza y se borra" {
    echo "paquete manipulado" >"$RAIZ/fuente"
    FALSA_DESCARGA="$RAIZ/fuente" run bash -c "source '$REPO/scripts/lib/comun.sh'; descargar_verificado https://ejemplo.org/p.deb '$RAIZ/p.deb' $(printf 'a%.0s' {1..64})"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no coincide"* ]]
    [ ! -f "$RAIZ/p.deb" ]
}

@test "no se permiten descargas sin HTTPS" {
    run bash -c "source '$REPO/scripts/lib/comun.sh'; descargar_verificado http://ejemplo.org/p.deb '$RAIZ/p.deb' $(printf 'a%.0s' {1..64})"
    [ "$status" -ne 0 ]
    [[ "$output" == *"HTTPS"* ]]
}

@test "las versiones fijadas tienen sumas SHA-256 bien formadas" {
    source "$REPO/versiones.conf"
    for v in ADGUARD_SHA256_ARM64 ADGUARD_SHA256_AMD64 PIHOLE_INSTALLER_SHA256 PICOCLAW_SHA256_ARM64_DEB; do
        [[ "${!v}" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$TAILSCALE_GPG_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]]
}

@test "las alertas no ponen el token de Telegram en la línea de comandos" {
    export TELEGRAM_TOKEN="123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" TELEGRAM_CHAT_ID="987654321"  # gitleaks:allow (token falso de prueba)
    run bash -c "source '$REPO/scripts/lib/comun.sh'; source <(sed -n '/^enviar_telegram()/,/^}/p' '$REPO/scripts/alertas.sh'); enviar_telegram 'hola'"
    [ "$status" -eq 0 ]
    nunca grep -q "$TELEGRAM_TOKEN" "$REGISTRO"
    grep -q "$TELEGRAM_TOKEN" "$REGISTRO.stdin"
}

@test "las alertas avisan una vez por problema y una vez al resolverse" {
    export TELEGRAM_TOKEN="123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" TELEGRAM_CHAT_ID="987654321"  # gitleaks:allow (token falso de prueba)
    export STATE_DIRECTORY="$RAIZ/estado"
    mkdir -p "$RAIZ/etc/exitnode"
    # systemctl falso: tailscaled caído
    mkdir -p "$RAIZ/bin"; printf '#!/bin/sh\nexit 3\n' >"$RAIZ/bin/systemctl"; chmod +x "$RAIZ/bin/systemctl"
    PATH="$RAIZ/bin:$PATH" run bash "$REPO/scripts/alertas.sh" --comprobar
    PATH="$RAIZ/bin:$PATH" run bash "$REPO/scripts/alertas.sh" --comprobar
    [ "$(grep -c 'sendMessage' "$REGISTRO.stdin")" -eq 1 ]
    grep -qx svc_tailscaled "$STATE_DIRECTORY/activas"
    # Se recupera
    printf '#!/bin/sh\nexit 0\n' >"$RAIZ/bin/systemctl"
    PATH="$RAIZ/bin:$PATH" run bash "$REPO/scripts/alertas.sh" --comprobar
    [ "$(grep -c 'sendMessage' "$REGISTRO.stdin")" -eq 2 ]
    nunca grep -qx svc_tailscaled "$STATE_DIRECTORY/activas"
}

@test "no se pueden instalar AdGuard y Pi-hole a la vez" {
    mkdir -p "$RAIZ/etc/pihole"; touch "$RAIZ/etc/pihole/pihole.toml"
    run bash "$REPO/scripts/bloqueador.sh" instalar adguard
    [ "$status" -ne 0 ]
    [[ "$output" == *"Pi-hole está instalado"* ]]
}

@test "el bloqueador no se instala si el puerto 53 está ocupado" {
    PUERTO53_OCUPADO=1 run bash "$REPO/scripts/bloqueador.sh" instalar adguard
    [ "$status" -ne 0 ]
    [[ "$output" == *"puerto 53"* ]]
}

@test "la plantilla de AdGuard no deja la contraseña sin rellenar ni el panel en local" {
    grep -q '@ADMIN_HASH@' "$REPO/config/plantillas/AdGuardHome.yaml"
    grep -q 'address: 0.0.0.0:8080' "$REPO/config/plantillas/AdGuardHome.yaml"
    grep -q 'ratelimit: 0' "$REPO/config/plantillas/AdGuardHome.yaml"
    grep -q 'https://dns.quad9.net/dns-query' "$REPO/config/plantillas/AdGuardHome.yaml"
}

@test "los servicios de systemd se ejecutan aislados" {
    for f in picoclaw.service adguardhome.service exitnode-alertas.service; do
        grep -qx 'NoNewPrivileges=yes' "$REPO/config/systemd/$f"
        grep -qx 'ProtectSystem=strict' "$REPO/config/systemd/$f"
    done
    grep -qx 'User=picoclaw' "$REPO/config/systemd/picoclaw.service"
    grep -qx 'CapabilityBoundingSet=' "$REPO/config/systemd/picoclaw.service"
    grep -qx 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' "$REPO/config/systemd/adguardhome.service"
    grep -qx 'DynamicUser=yes' "$REPO/config/systemd/exitnode-alertas.service"
}

@test "el panel de estado detecta el exit node aprobado leyendo bien el JSON" {
    cat >"$RAIZ/ts.json" <<'EOF'
{
  "BackendState": "Running",
  "Self": {
    "HostName": "raspberrypi",
    "TailscaleIPs": ["100.101.102.103"],
    "ExitNodeOption": true,
    "KeyExpiry": "2027-04-28T10:00:00Z"
  }
}
EOF
    FALSO_TS_JSON="$RAIZ/ts.json" run bash "$REPO/scripts/status.sh" --texto
    [[ "$output" == *"Conectado como raspberrypi (100.101.102.103)"* ]]
    [[ "$output" == *"Aprobado como exit node"* ]]
    [[ "$output" != *"Aún no aprobado"* ]]
}

@test "una instalación antigua de AdGuard se migra conservando su configuración" {
    mkdir -p "$RAIZ/opt/AdGuardHome/data" "$RAIZ/etc/systemd/system"
    printf '#!/bin/sh\n' >"$RAIZ/opt/AdGuardHome/AdGuardHome"; chmod +x "$RAIZ/opt/AdGuardHome/AdGuardHome"
    echo "users: [{name: ricardo, password: hash-antiguo}]" >"$RAIZ/opt/AdGuardHome/AdGuardHome.yaml"
    echo "stats" >"$RAIZ/opt/AdGuardHome/data/stats.db"
    touch "$RAIZ/etc/systemd/system/AdGuardHome.service"
    SIMULAR=1 run bash "$REPO/scripts/bloqueador.sh" instalar adguard
    [ "$status" -eq 0 ]
    [[ "$output" == *"systemctl disable --now AdGuardHome.service"* ]]
    [[ "$output" == *"AdGuardHome.yaml $RAIZ/var/lib/adguardhome/AdGuardHome.yaml"* ]]
    [[ "$output" == *"Configuración anterior migrada"* ]]
    # No genera una contraseña nueva que sustituya a la que ya tenía.
    nunca grep -q "Contraseña:" <<<"$output"
}

@test "el informe de PicoClaw no lo escribe root en la carpeta del usuario picoclaw" {
    grep -q 'runuser -u picoclaw' "$REPO/config/systemd/picoclaw-estado.service"
    nunca grep -qE "> /var/lib/picoclaw/workspace/[^\"]*; chown" "$REPO/config/systemd/picoclaw-estado.service"
}
