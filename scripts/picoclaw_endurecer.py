#!/usr/bin/env python3
"""Aplica una configuración segura a PicoClaw después de `picoclaw onboard`.

Qué hace:
  - Exige una lista de usuarios permitidos en cada canal activo (sin ella,
    PicoClaw acepta mensajes de cualquiera).
  - Desactiva la ejecución de comandos y las herramientas que escriben,
    descargan o instalan cosas. El asistente solo puede leer su carpeta de trabajo.
  - Deja el gateway escuchando solo en 127.0.0.1.
  - Ajusta los permisos de los ficheros de configuración y secretos.

Devuelve 0 si la configuración queda segura, 1 si hay algo que el usuario
tiene que corregir antes de arrancar el servicio.
"""

import argparse
import json
import os
import re
import sys
import tempfile

HERRAMIENTAS_DESACTIVADAS = [
    "install_skill", "spawn", "subagent", "write_file", "edit_file",
    "append_file", "web_fetch", "web", "skills", "find_skills", "cron",
    "mcp", "i2c", "serial", "spi",
]
HERRAMIENTAS_PERMITIDAS = ["read_file", "list_dir", "message"]
VALORES_DE_EJEMPLO = {"YOUR_USER_ID", "", "*"}


def fallo(msg):
    print(f"  [ERROR] {msg}", file=sys.stderr)


def aviso(msg):
    print(f"  [AVISO] {msg}", file=sys.stderr)


def ok(msg):
    print(f"  [OK]    {msg}")


def guardar(ruta, datos):
    d = os.path.dirname(ruta)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".config.", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(datos, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, ruta)


def endurecer(cfg, workspace, permitir_comandos):
    problemas = []

    if int(cfg.get("version", 0)) < 3:
        problemas.append(
            "La configuración es de una versión antigua de PicoClaw. "
            "Vuelve a ejecutar 'picoclaw onboard' con la versión instalada."
        )
        return problemas

    # 1. Canales: todos los activos necesitan lista de permitidos.
    canales = cfg.get("channel_list") or {}
    activos = 0
    for nombre, canal in canales.items():
        if not isinstance(canal, dict) or not canal.get("enabled"):
            continue
        permitidos = [str(x).strip() for x in (canal.get("allow_from") or [])]
        if not permitidos or any(p in VALORES_DE_EJEMPLO for p in permitidos):
            problemas.append(
                f"El canal '{nombre}' está activo sin lista de usuarios permitidos (allow_from). "
                "Cualquiera que encuentre el bot podría usarlo."
            )
            continue
        if nombre == "telegram" and not all(re.fullmatch(r"-?\d{5,15}", p) for p in permitidos):
            problemas.append(
                "En Telegram, allow_from debe contener tu ID numérico (te lo da @userinfobot), "
                "no tu nombre de usuario: los nombres se pueden cambiar o suplantar."
            )
            continue
        activos += 1
        ok(f"Canal '{nombre}': solo responde a {', '.join(permitidos)}")
    if activos == 0 and not problemas:
        problemas.append("No hay ningún canal activo. Configura Telegram con 'picoclaw onboard'.")

    # 2. El asistente solo puede tocar su carpeta de trabajo.
    agentes = cfg.setdefault("agents", {})
    defecto = agentes.setdefault("defaults", {})
    defecto["restrict_to_workspace"] = True
    defecto["workspace"] = workspace
    for ag in agentes.get("agents") or []:
        if isinstance(ag, dict):
            ag["restrict_to_workspace"] = True
    ok(f"Carpeta de trabajo limitada a {workspace}")

    # 3. Herramientas.
    tools = cfg.setdefault("tools", {})
    tools["allow_read_paths"] = []
    tools["allow_write_paths"] = []
    for h in HERRAMIENTAS_DESACTIVADAS:
        t = tools.setdefault(h, {})
        if isinstance(t, dict):
            t["enabled"] = False
    for h in HERRAMIENTAS_PERMITIDAS:
        t = tools.setdefault(h, {})
        if isinstance(t, dict):
            t["enabled"] = True
    ex = tools.setdefault("exec", {})
    if permitir_comandos:
        ex["enabled"] = True
        ex["enable_deny_patterns"] = True
        aviso(
            "Ejecución de comandos ACTIVADA por --permitir-comandos. PicoClaw tiene una "
            "vulnerabilidad de inyección de comandos sin parche (CVE-2026-36045). "
            "Úsalo solo si entiendes el riesgo."
        )
    else:
        ex["enabled"] = False
        ok("Ejecución de comandos desactivada (solo lectura del informe de estado)")
    ok("Desactivadas: " + ", ".join(HERRAMIENTAS_DESACTIVADAS))

    # 4. Gateway solo en local.
    gw = cfg.setdefault("gateway", {})
    gw["host"] = "127.0.0.1"
    ok("Gateway escuchando solo en 127.0.0.1")

    return problemas


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--home", default="/var/lib/picoclaw/.picoclaw")
    p.add_argument("--workspace", default="/var/lib/picoclaw/workspace")
    p.add_argument("--permitir-comandos", action="store_true")
    p.add_argument("--comprobar", action="store_true", help="solo comprueba, no escribe")
    a = p.parse_args()

    ruta = os.path.join(a.home, "config.json")
    if not os.path.isfile(ruta):
        fallo(f"No existe {ruta}. Ejecuta primero el asistente: picoclaw onboard")
        return 1
    with open(ruta) as f:
        cfg = json.load(f)

    problemas = endurecer(cfg, a.workspace, a.permitir_comandos)
    if not a.comprobar:
        guardar(ruta, cfg)
        os.chmod(a.home, 0o700)
        seg = os.path.join(a.home, ".security.yml")
        if os.path.isfile(seg):
            os.chmod(seg, 0o600)
            ok("Secretos en .security.yml con permisos 600")
        else:
            aviso("No hay .security.yml: los secretos están en config.json (permisos 600).")

    for pr in problemas:
        fallo(pr)
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
