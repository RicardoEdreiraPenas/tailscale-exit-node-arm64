#!/usr/bin/env bash
# Desactiva el acceso SSH por contraseña y deja solo el acceso con clave.
#
# Uso: sudo bash scripts/endurecer_ssh.sh
#
# Antes de tocar nada comprueba que tu usuario ya tiene una clave autorizada,
# para que no te quedes fuera. Si no la tiene, explica cómo añadirla.

source "$(dirname "${BASH_SOURCE[0]}")/lib/comun.sh"
for arg in "$@"; do [[ "$arg" == "--simular" ]] && SIMULAR=1; done
requiere_root

USUARIO="${SUDO_USER:-}"
[[ -n "$USUARIO" && "$USUARIO" != "root" ]] || morir "Ejecútalo con sudo desde tu usuario normal, no como root."
CLAVES="$(getent passwd "$USUARIO" | cut -d: -f6)/.ssh/authorized_keys"

if ! grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2|sk-)' "$(r "$CLAVES")" 2>/dev/null; then
    cat <<EOF
  Tu usuario ($USUARIO) todavía no tiene ninguna clave SSH autorizada.
  Desde tu ordenador (Mac, Linux o Windows con PowerShell):

    ssh-keygen -t ed25519                         # si aún no tienes una clave
    ssh-copy-id $USUARIO@$(hostname).local         # copia la clave a la placa

  Comprueba que entras sin contraseña y vuelve a ejecutar este script.
EOF
    exit 1
fi

escribir_fichero /etc/ssh/sshd_config.d/10-exitnode.conf 0644 <<'EOF'
# Creado por scripts/endurecer_ssh.sh
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF

if [[ "$SIMULAR" != "1" ]]; then
    if ! sshd -t; then
        rm -f /etc/ssh/sshd_config.d/10-exitnode.conf
        morir "La configuración de SSH no es válida; la he retirado y no he cambiado nada."
    fi
    if ! sshd -T | grep -qx 'passwordauthentication no'; then
        aviso "Otro fichero de configuración vuelve a activar las contraseñas. Revisa /etc/ssh/sshd_config y /etc/ssh/sshd_config.d/."
    fi
fi
ejecutar systemctl reload ssh
ok "SSH solo acepta claves. No cierres esta sesión hasta comprobar que entras desde otra terminal."
