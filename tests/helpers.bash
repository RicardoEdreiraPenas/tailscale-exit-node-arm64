# Preparación común: un sistema de ficheros falso en $RAIZ y comandos del sistema
# sustituidos por los de tests/shims, que solo registran lo que se les pide.

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

preparar() {
    RAIZ="$(mktemp -d)"
    REGISTRO="$RAIZ/.registro"
    export RAIZ REGISTRO NO_INTERACTIVO=1
    export PATH="$REPO/tests/shims:$PATH"
    : >"$REGISTRO"
    mkdir -p "$RAIZ"/etc/{sysctl.d,apt/apt.conf.d,apt/sources.list.d,systemd/system,ssh/sshd_config.d} \
             "$RAIZ"/usr/share/keyrings "$RAIZ"/usr/local/lib "$RAIZ"/var/lib
    echo "12.7" >"$RAIZ/etc/debian_version"
    cat >"$RAIZ/etc/os-release" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
ID=debian
VERSION_CODENAME=bookworm
EOF
}

limpiar() {
    [[ -n "${RAIZ:-}" && -d "$RAIZ" ]] && rm -rf "$RAIZ"
}

# ¿Se llamó a este comando con estos argumentos?
llamado() {
    grep -qF -- "$*" "$REGISTRO"
}

# Falla si el comando tiene éxito. (En bats, una línea "! comando" no hace fallar la prueba.)
nunca() {
    if "$@"; then
        echo "No debería cumplirse: $*" >&2
        return 1
    fi
}
