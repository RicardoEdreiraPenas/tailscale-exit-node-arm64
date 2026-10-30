#!/usr/bin/env bash
# Deshace lo que instala este proyecto. Pregunta antes de quitar Tailscale y el cortafuegos.
#
# Uso: sudo bash scripts/uninstall.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"
[[ " ${*} " == *" --simular "* ]] && SIMULAR=1
requiere_root
leer_config

titulo "Desinstalación"

[[ "${PICOCLAW:-no}" == "si" || -f "$(r /etc/systemd/system/picoclaw.service)" ]] && bash "$DIR_REPO/scripts/picoclaw.sh" desinstalar
[[ "$BLOQUEADOR" != "ninguno" ]] && bash "$DIR_REPO/scripts/bloqueador.sh" desinstalar

ejecutar systemctl disable --now exitnode-alertas.timer exitnode-gro.service 2>/dev/null || true
ejecutar rm -f "$(r /etc/systemd/system/exitnode-alertas.service)" "$(r /etc/systemd/system/exitnode-alertas.timer)" \
               "$(r /etc/systemd/system/exitnode-gro.service)"
ejecutar rm -rf "$(r /usr/local/lib/exitnode)"
ejecutar systemctl daemon-reload
ok "Servicios del proyecto retirados"

ejecutar rm -f "$(r /etc/sysctl.d/99-exitnode.conf)" "$(r /etc/apt/apt.conf.d/52exitnode-tailscale)" \
               "$(r /etc/ssh/sshd_config.d/10-exitnode.conf)"
# Recarga la configuración del sistema en lugar de forzar valores: si otra cosa necesita el reenvío, lo conserva.
ejecutar sysctl -q --system
ok "Reenvío de paquetes devuelto a la configuración del sistema"
ejecutar systemctl reload ssh 2>/dev/null || true

if command -v ufw >/dev/null 2>&1 && confirmar "¿Desactivar el cortafuegos (ufw)?" n; then
    ejecutar ufw --force disable
fi

if command -v tailscale >/dev/null 2>&1 && confirmar "¿Desinstalar también Tailscale?" n; then
    ejecutar tailscale down || true
    ejecutar apt-get remove --purge -y tailscale
    ejecutar rm -f "$(r /etc/apt/sources.list.d/tailscale.list)" "$(r /usr/share/keyrings/tailscale-archive-keyring.gpg)"
fi

ejecutar rm -rf "$(r "$DIR_CONF")"
ok "Desinstalación completada"
