#!/usr/bin/env bash
# Funciones compartidas por todos los scripts.
#
# Variables que cambian el comportamiento (pensadas para las pruebas):
#   RAIZ      prefijo para todas las rutas del sistema (por defecto, vacío = /)
#   SIMULAR   si vale 1, los comandos que cambian el sistema solo se muestran
#   NO_INTERACTIVO  si vale 1, no se hacen preguntas y se usa la opción segura

# shellcheck disable=SC2034  # algunas variables se usan desde otros scripts

set -o errexit -o nounset -o pipefail
IFS=$'\n\t'
umask 022

DIR_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAIZ="${RAIZ:-}"
SIMULAR="${SIMULAR:-0}"
NO_INTERACTIVO="${NO_INTERACTIVO:-0}"
# Los scripts que llaman a otros (install.sh -> bloqueador.sh) les pasan el modo.
export SIMULAR NO_INTERACTIVO

DIR_CONF="/etc/exitnode"
DIR_ESTADO="/var/lib/exitnode"

if [[ -t 1 ]]; then
    _V=$'\033[0;32m' _R=$'\033[0;31m' _A=$'\033[1;33m' _N=$'\033[1m' _X=$'\033[0m'
else
    _V='' _R='' _A='' _N='' _X=''
fi

info()  { local IFS=' '; printf '%s\n' "  $*"; }
ok()    { local IFS=' '; printf '%s\n' "  ${_V}[OK]${_X}    $*"; }
aviso() { local IFS=' '; printf '%s\n' "  ${_A}[AVISO]${_X} $*" >&2; }
error() { local IFS=' '; printf '%s\n' "  ${_R}[ERROR]${_X} $*" >&2; }
morir() { local IFS=' '; error "$*"; exit 1; }
titulo() { local IFS=' '; printf '\n%s\n' "${_N}== $* ==${_X}"; }

# Ruta real de un fichero del sistema, teniendo en cuenta RAIZ.
r() { printf '%s%s' "$RAIZ" "$1"; }

# Ejecuta un comando que cambia el sistema. En modo simulación solo lo muestra.
ejecutar() {
    if [[ "$SIMULAR" == "1" ]]; then
        local IFS=' '
        printf '  [simulado] %s\n' "$*"
        return 0
    fi
    "$@"
}

requiere_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 && "$SIMULAR" != "1" && -z "$RAIZ" ]]; then
        local IFS=' '; morir "Ejecuta este script con sudo: sudo bash $0 ${*:-}"
    fi
}

requiere_comando() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || morir "Falta el comando '$c'. Instálalo con: sudo apt install $c"
    done
}

cargar_versiones() {
    # shellcheck source=../../versiones.conf
    source "$DIR_REPO/versiones.conf"
}

# arm64 o amd64, con los nombres que usan las descargas.
arquitectura() {
    case "$(uname -m)" in
        aarch64|arm64) echo arm64 ;;
        x86_64|amd64)  echo amd64 ;;
        *) morir "Arquitectura $(uname -m) no soportada. Este proyecto es para ARM64." ;;
    esac
}

# Pregunta sí/no. Sin terminal o con NO_INTERACTIVO=1 devuelve la respuesta por defecto.
confirmar() {
    local pregunta="$1" defecto="${2:-n}" respuesta
    if [[ "$NO_INTERACTIVO" == "1" || ! -t 0 ]]; then
        [[ "$defecto" == "s" ]]
        return
    fi
    read -r -p "  $pregunta [$( [[ $defecto == s ]] && echo 'S/n' || echo 's/N')] " respuesta
    respuesta="${respuesta:-$defecto}"
    [[ "$respuesta" =~ ^[sS]$ ]]
}

# Descarga un fichero por HTTPS y comprueba su SHA-256.
# Si la suma no coincide, borra el fichero y se detiene.
descargar_verificado() {
    local url="$1" destino="$2" esperado="$3" obtenido
    [[ "$url" == https://* ]] || morir "Solo se permiten descargas por HTTPS: $url"
    [[ "$esperado" =~ ^[0-9a-f]{64}$ ]] || morir "Suma SHA-256 mal formada para $url"
    info "Descargando $url"
    if [[ "$SIMULAR" == "1" ]]; then
        printf '  [simulado] descarga y comprobación de %s\n' "$destino"
        return 0
    fi
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
         --retry 3 --retry-delay 2 --max-time 300 -o "$destino" "$url" \
        || morir "No se pudo descargar $url"
    obtenido="$(sha256sum "$destino" | awk '{print $1}')"
    if [[ "$obtenido" != "$esperado" ]]; then
        rm -f "$destino"
        morir "La suma SHA-256 de $(basename "$destino") no coincide. Esperada $esperado, obtenida $obtenido. No se instala nada."
    fi
    ok "Descarga verificada: $(basename "$destino")"
}

# Contraseña aleatoria de 20 caracteres. (Con "tr < /dev/urandom | head" el pipeline
# devuelve SIGPIPE y, con pipefail, abortaría el script.)
contrasena_aleatoria() {
    LC_ALL=C tr -dc 'A-Za-z0-9' < <(head -c 600 /dev/urandom) | cut -c1-20
}

# Comprueba que una ruta no es un enlace simbólico (ni ella ni la carpeta que la contiene).
# Root nunca debe escribir a través de un enlace que pueda haber puesto otro usuario.
sin_enlaces() {
    local ruta
    for ruta in "$@"; do
        if [[ -L "$ruta" || -L "$(dirname "$ruta")" ]]; then
            morir "$ruta (o su carpeta) es un enlace simbólico. Por seguridad no sigo: revisa quién lo ha creado."
        fi
    done
}

# Ejecuta un comando como otro usuario, sin abrir una sesión PAM.
como_usuario() {
    local usuario="$1"; shift
    ejecutar setpriv --reuid="$usuario" --regid="$usuario" --init-groups --reset-env -- "$@"
}

# Escribe la entrada estándar en un fichero con permisos y dueño concretos.
# Si ya existía con otro contenido, guarda una copia .bak con fecha.
escribir_fichero() {
    local destino modo dueno tmp
    destino="$(r "$1")" modo="${2:-0644}" dueno="${3:-root:root}"
    tmp="$(mktemp)"
    cat >"$tmp"
    if [[ "$SIMULAR" == "1" ]]; then
        printf '  [simulado] escribir %s (%s %s)\n' "$1" "$modo" "$dueno"
        rm -f "$tmp"
        return 0
    fi
    mkdir -p "$(dirname "$destino")"
    sin_enlaces "$destino"
    # Copia de seguridad solo en carpetas de root: en una carpeta de otro usuario, ese usuario
    # podría dejar preparado un enlace con el nombre de la copia.
    if [[ -f "$destino" ]] && ! cmp -s "$tmp" "$destino" && [[ "$(stat -c %u "$(dirname "$destino")")" == "0" ]]; then
        cp -P --preserve=mode,timestamps "$destino" "$destino.bak.$(date +%Y%m%d%H%M%S)"
    fi
    install -m "$modo" "$tmp" "$destino"
    if [[ -z "$RAIZ" ]]; then
        chown "$dueno" "$destino"
    fi
    rm -f "$tmp"
}

# Interfaz que sale a internet (la de la ruta por defecto).
interfaz_salida() {
    ip -4 route show default 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

# Subred local de una interfaz, p. ej. 192.168.1.0/24.
subred_lan() {
    local iface="$1"
    ip -4 route show dev "$iface" proto kernel scope link 2>/dev/null | awk 'NR==1 {print $1}'
}

puerto_ocupado() {
    local puerto="$1"
    ss -Hlnu "sport = :$puerto" 2>/dev/null | grep -q . || ss -Hlnt "sport = :$puerto" 2>/dev/null | grep -q .
}

servicio_activo() { systemctl is-active --quiet "$1" 2>/dev/null; }

leer_config() {
    local f
    f="$(r "$DIR_CONF/exitnode.conf")"
    if [[ -f "$f" ]]; then
        # shellcheck source=/dev/null
        source "$f"
    fi
    BLOQUEADOR="${BLOQUEADOR:-ninguno}"
}

guardar_config() {
    local clave="$1" valor="$2" f
    f="$(r "$DIR_CONF/exitnode.conf")"
    [[ "$valor" =~ ^[A-Za-z0-9._/:-]*$ ]] || morir "Valor de configuración no válido para $clave"
    if [[ "$SIMULAR" == "1" ]]; then
        printf '  [simulado] %s=%s en %s\n' "$clave" "$valor" "$DIR_CONF/exitnode.conf"
        return 0
    fi
    mkdir -p "$(dirname "$f")"
    touch "$f"
    chmod 0644 "$f"
    if grep -q "^${clave}=" "$f"; then
        sed -i "s|^${clave}=.*|${clave}=\"${valor}\"|" "$f"
    else
        printf '%s="%s"\n' "$clave" "$valor" >>"$f"
    fi
}
