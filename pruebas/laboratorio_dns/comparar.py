#!/usr/bin/env python3
"""Compara AdGuard Home y Pi-hole (FTL) en las mismas condiciones.

Arranca un DNS de origen simulado con retardo fijo, los dos bloqueadores con la
misma lista de bloqueo y mide, para cada uno:
  - eficacia: dominios de anuncios bloqueados y falsos positivos en webs normales
  - latencia (p50, p95, p99) en tres casos: respuesta en caché, consulta nueva
    que tiene que salir al origen y dominio bloqueado
  - consultas por segundo que aguanta limitado a un núcleo de CPU
  - memoria (RSS) y CPU consumida

No necesita internet ni contenedores. Se ejecuta como root (Pi-hole usa /etc/pihole).

Uso:
  sudo python3 comparar.py --adguard /ruta/AdGuardHome --ftl /ruta/pihole-FTL \
       --pihole-core /ruta/repo-pi-hole --lista hosts.txt --prueba-anuncios adblock_data.json \
       --plantillas ../../config/plantillas --salida resultados
"""

import argparse
import asyncio
import json
import os
import random
import re
import shutil
import signal
import socket
import sqlite3
import statistics
import struct
import subprocess
import sys
import tempfile
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
PUERTO_ORIGEN, PUERTO_AG, PUERTO_PH = 5300, 5301, 5302
NUCLEO = "0"  # los bloqueadores se limitan a un núcleo para acercarse a una Raspberry

DOMINIOS_NORMALES = """
google.com youtube.com facebook.com instagram.com whatsapp.com wikipedia.org amazon.es
netflix.com spotify.com apple.com microsoft.com office.com live.com outlook.com github.com
stackoverflow.com linkedin.com twitter.com x.com reddit.com twitch.tv tiktok.com
elpais.com elmundo.es marca.com as.com rtve.es abc.es lavanguardia.com 20minutos.es
eldiario.es elconfidencial.com expansion.com cincodias.elpais.com idealista.com fotocasa.es
wallapop.com milanuncios.com renfe.com aena.es agenciatributaria.gob.es seg-social.es
sede.gob.es boe.es gva.es valencia.es uv.es upv.es edem.es tailscale.com cloudflare.com
quad9.net mozilla.org debian.org raspberrypi.com python.org pypi.org npmjs.com docker.com
zoom.us teams.microsoft.com slack.com notion.so dropbox.com drive.google.com docs.google.com
mail.google.com maps.google.com play.google.com bbc.com nytimes.com theguardian.com
booking.com airbnb.es ryanair.com vueling.com iberia.com decathlon.es ikea.com leroymerlin.es
mercadona.es carrefour.es elcorteingles.es pccomponentes.com mediamarkt.es fnac.es
bbva.es santander.com caixabank.es ing.es openbank.es paypal.com bizum.es
""".split()


# ---------------------------------------------------------------- consultas DNS
def paquete_consulta(nombre, ident, qtype=1):
    q = b"".join(bytes([len(p)]) + p.encode() for p in nombre.strip(".").split(".")) + b"\x00"
    return struct.pack("!HHHHHH", ident, 0x0100, 1, 0, 0, 0) + q + struct.pack("!HH", qtype, 1)


def leer_respuesta(datos):
    """Devuelve (rcode, lista de IPv4 de la respuesta)."""
    ident, flags, qd, an = struct.unpack("!HHHH", datos[:8])
    rcode = flags & 0xF
    i = 12
    for _ in range(qd):
        while datos[i] != 0:
            if datos[i] & 0xC0 == 0xC0:
                i += 1
                break
            i += datos[i] + 1
        i += 5
    ips = []
    for _ in range(an):
        if datos[i] & 0xC0 == 0xC0:
            i += 2
        else:
            while datos[i] != 0:
                i += datos[i] + 1
            i += 1
        tipo, _, _, rdlen = struct.unpack("!HHIH", datos[i:i + 10])
        i += 10
        if tipo == 1 and rdlen == 4:
            ips.append(socket.inet_ntoa(datos[i:i + 4]))
        i += rdlen
    return rcode, ips


async def consultar_muchos(puerto, nombres, concurrencia=8, timeout=3.0):
    """Lanza las consultas con concurrencia limitada. Devuelve [(nombre, ms, rcode, ips)]."""
    loop = asyncio.get_running_loop()
    resultados = []
    sem = asyncio.Semaphore(concurrencia)

    async def una(nombre):
        async with sem:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setblocking(False)
            ident = random.randrange(65536)
            t0 = time.perf_counter()
            try:
                await loop.sock_sendto(s, paquete_consulta(nombre, ident), ("127.0.0.1", puerto))
                datos = await asyncio.wait_for(loop.sock_recv(s, 4096), timeout)
                ms = (time.perf_counter() - t0) * 1000
                rcode, ips = leer_respuesta(datos)
                if rcode not in (0, 3):  # solo NOERROR y NXDOMAIN son respuestas válidas
                    ms = None
                resultados.append((nombre, ms, rcode, ips))
            except asyncio.TimeoutError:
                resultados.append((nombre, None, None, []))
            finally:
                s.close()

    await asyncio.gather(*(una(n) for n in nombres))
    return resultados


def bloqueado(rcode, ips):
    return rcode == 3 or (rcode == 0 and (not ips or all(ip in ("0.0.0.0", "127.0.0.1") for ip in ips)))


def percentiles(valores):
    v = sorted(x for x in valores if x is not None)
    if not v:
        return {}
    p = lambda q: v[min(len(v) - 1, int(q * len(v)))]
    return {"n": len(v), "media": round(statistics.mean(v), 2), "p50": round(p(0.50), 2),
            "p95": round(p(0.95), 2), "p99": round(p(0.99), 2), "max": round(v[-1], 2),
            "errores_o_perdidas": sum(1 for x in valores if x is None)}


# ---------------------------------------------------------------- procesos
def esperar_puerto(puerto, segundos=60):
    fin = time.time() + segundos
    while time.time() < fin:
        try:
            r = asyncio.run(consultar_muchos(puerto, ["example.com"], 1, 1.0))
            if r and r[0][1] is not None:
                return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def rss_kb(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for l in f:
                if l.startswith("VmRSS:"):
                    return int(l.split()[1])
    except OSError:
        return None


def cpu_seg(pid):
    with open(f"/proc/{pid}/stat") as f:
        campos = f.read().rsplit(")", 1)[1].split()
    return (int(campos[11]) + int(campos[12])) / os.sysconf("SC_CLK_TCK")


def arrancar_adguard(a, dominios_lista, trabajo):
    d = os.path.join(trabajo, "adguard")
    os.makedirs(os.path.join(d, "userfilters"), exist_ok=True)
    lista = os.path.join(d, "userfilters", "lista.txt")
    shutil.copy(a.lista, lista)
    cfg = open(os.path.join(a.plantillas, "AdGuardHome.yaml")).read()
    hash_ = subprocess.run(["htpasswd", "-nbBC", "10", "admin", "prueba-laboratorio"],
                           capture_output=True, text=True, check=True).stdout.strip().split(":", 1)[1]
    cfg = cfg.replace("@ADMIN_USER@", "admin").replace("@ADMIN_HASH@", hash_)
    cfg = cfg.replace("address: 0.0.0.0:8080", "address: 127.0.0.1:8081")
    cfg = cfg.replace("    - 0.0.0.0\n  port: 53", f"    - 127.0.0.1\n  port: {PUERTO_AG}")
    cfg = re.sub(r"  upstream_dns:\n(    - .*\n)+", f"  upstream_dns:\n    - 127.0.0.1:{PUERTO_ORIGEN}\n", cfg)
    cfg = re.sub(r"  fallback_dns:\n(    - .*\n)+", "  fallback_dns: []\n", cfg)
    cfg = cfg.replace("/var/lib/adguardhome/userfilters/*", os.path.join(d, "userfilters", "*"))
    cfg = re.sub(r"filters:\n(  - .*\n(    .*\n)*)+?whitelist_filters",
                 f"filters:\n  - enabled: true\n    url: {lista}\n    name: Lista comun\n    id: 1\nwhitelist_filters", cfg)
    ruta = os.path.join(d, "AdGuardHome.yaml")
    open(ruta, "w").write(cfg)
    p = subprocess.Popen(["taskset", "-c", NUCLEO, a.adguard, "--no-check-update", "-c", ruta, "-w", d],
                         stdout=open(os.path.join(d, "salida.log"), "w"), stderr=subprocess.STDOUT)
    return p


def arrancar_pihole(a, dominios_lista, trabajo):
    etc = "/etc/pihole"
    if os.path.exists(etc):
        shutil.move(etc, etc + ".antes-del-laboratorio." + str(int(time.time())))
    os.makedirs(etc)
    os.makedirs("/var/log/pihole", exist_ok=True)
    toml = open(os.path.join(a.plantillas, "pihole.toml")).read()
    toml = toml.replace('upstreams = ["9.9.9.9", "149.112.112.112", "1.1.1.1"]',
                        f'upstreams = ["127.0.0.1#{PUERTO_ORIGEN}"]\n  port = {PUERTO_PH}')
    toml = toml.replace('port = "8080o,[::]:8080o"', 'port = "127.0.0.1:8082"')
    # El origen simulado no firma con DNSSEC: con la validación activa, Pi-hole lo rechazaría todo.
    # AdGuard solo pide DNSSEC al origen y no valida, así que se desactiva para comparar igual.
    toml = toml.replace("dnssec = true", "dnssec = false")
    # Pi-hole limita por defecto a 1000 consultas por minuto y cliente. En casa cada dispositivo
    # tiene su IP y no llega, pero aquí todo sale de 127.0.0.1: se desactiva, como en AdGuard.
    toml = toml.replace("[dns.cache]", "[dns.rateLimit]\n    count = 0\n    interval = 0\n  [dns.cache]")
    open(os.path.join(etc, "pihole.toml"), "w").write(toml)
    # gravity.db con el esquema oficial y la misma lista que AdGuard
    db = sqlite3.connect(os.path.join(etc, "gravity.db"))
    db.executescript(open(os.path.join(a.pihole_core, "advanced/Templates/gravity.db.sql")).read())
    db.execute("INSERT INTO adlist (id, address, enabled, comment) VALUES (1, 'file:///lab/lista.txt', 1, 'Lista comun')")
    db.executemany("INSERT INTO gravity (domain, adlist_id) VALUES (?, 1)", ((d,) for d in dominios_lista))
    # Lo mismo que hace gravity.sh al terminar: índice y fecha de actualización.
    db.execute("CREATE INDEX IF NOT EXISTS idx_gravity ON gravity (domain, adlist_id)")
    db.execute("INSERT OR REPLACE INTO info (property, value) VALUES ('updated', cast(strftime('%s','now') as int))")
    db.execute("INSERT OR REPLACE INTO info (property, value) VALUES ('gravity_count', ?)", (len(dominios_lista),))
    db.commit()
    db.close()
    p = subprocess.Popen(["taskset", "-c", NUCLEO, a.ftl, "no-daemon"],
                         stdout=open(os.path.join(trabajo, "pihole-salida.log"), "w"), stderr=subprocess.STDOUT)
    return p


def dnsperf_qps(puerto, fichero, segundos=15):
    r = subprocess.run(["dnsperf", "-s", "127.0.0.1", "-p", str(puerto), "-d", fichero, "-l", str(segundos),
                        "-c", "20", "-T", "2", "-q", "500"], capture_output=True, text=True)
    m = re.search(r"Queries per second:\s+([\d.]+)", r.stdout)
    l = re.search(r"Average Latency \(s\):\s+([\d.]+)", r.stdout)
    perd = re.search(r"Queries lost:\s+(\d+)", r.stdout)
    codigos = re.search(r"Response codes:\s+(.*)", r.stdout)
    return {"qps": float(m.group(1)) if m else None,
            "latencia_media_ms": round(float(l.group(1)) * 1000, 2) if l else None,
            "perdidas": int(perd.group(1)) if perd else None,
            "codigos_respuesta": codigos.group(1).strip() if codigos else None}


# ---------------------------------------------------------------- principal
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adguard", required=True)
    ap.add_argument("--ftl", required=True)
    ap.add_argument("--pihole-core", required=True)
    ap.add_argument("--lista", required=True)
    ap.add_argument("--prueba-anuncios", required=True)
    ap.add_argument("--plantillas", default=os.path.join(AQUI, "..", "..", "config", "plantillas"))
    ap.add_argument("--salida", default="resultados")
    ap.add_argument("--retardo-ms", type=float, default=20)
    a = ap.parse_args()
    random.seed(2026)
    os.makedirs(a.salida, exist_ok=True)
    trabajo = tempfile.mkdtemp(prefix="lab-dns-")

    dominios_lista = sorted({l.split()[1].lower() for l in open(a.lista, encoding="utf-8", errors="ignore")
                             if l.startswith("0.0.0.0 ") and len(l.split()) >= 2 and l.split()[1] != "0.0.0.0"})
    anuncios = []

    def recoger(x):
        if isinstance(x, dict):
            for v in x.values():
                recoger(v)
        elif isinstance(x, list):
            for i in x:
                if isinstance(i, str):
                    anuncios.append(i)
                else:
                    recoger(i)
    recoger(json.load(open(a.prueba_anuncios)))
    anuncios = sorted(set(anuncios))
    muestra_lista = random.sample(dominios_lista, 2000)

    origen = subprocess.Popen([sys.executable, os.path.join(AQUI, "upstream_simulado.py"),
                               "--puerto", str(PUERTO_ORIGEN), "--retardo-ms", str(a.retardo_ms)],
                              stdout=subprocess.PIPE, text=True)
    time.sleep(1)
    procesos = {}
    resultados = {"condiciones": {
        "lista_bloqueo_dominios": len(dominios_lista), "retardo_origen_ms": a.retardo_ms,
        "cpu_limitada_a_nucleos": 1, "dominios_prueba_anuncios": len(anuncios),
        "dominios_normales": len(DOMINIOS_NORMALES)}}
    try:
        procesos["adguard"] = arrancar_adguard(a, dominios_lista, trabajo)
        procesos["pihole"] = arrancar_pihole(a, dominios_lista, trabajo)
        puertos = {"adguard": PUERTO_AG, "pihole": PUERTO_PH, "sin bloqueador": PUERTO_ORIGEN}
        for n in ("adguard", "pihole"):
            if not esperar_puerto(puertos[n], 90):
                raise SystemExit(f"{n} no arrancó; mira los registros en {trabajo}")
        time.sleep(8)  # que terminen de cargar la lista

        # Ficheros para dnsperf
        f_cache = os.path.join(trabajo, "cache.txt")
        f_nuevas = os.path.join(trabajo, "nuevas.txt")
        f_bloq = os.path.join(trabajo, "bloqueadas.txt")
        open(f_cache, "w").write("".join(f"{d} A\n" for d in DOMINIOS_NORMALES))
        open(f_bloq, "w").write("".join(f"{d} A\n" for d in muestra_lista[:500]))

        for nombre, puerto in puertos.items():
            r = {}
            pid = procesos[nombre].pid if nombre in procesos else origen.pid
            cpu0 = cpu_seg(pid)
            if nombre != "sin bloqueador":
                res = asyncio.run(consultar_muchos(puerto, muestra_lista))
                r["bloqueo_lista_comun"] = f"{sum(bloqueado(x[2], x[3]) for x in res)}/{len(res)}"
                res = asyncio.run(consultar_muchos(puerto, anuncios))
                ok = [x[0] for x in res if bloqueado(x[2], x[3])]
                r["bloqueo_prueba_anuncios"] = f"{len(ok)}/{len(anuncios)}"
                res = asyncio.run(consultar_muchos(puerto, DOMINIOS_NORMALES))
                fp = [x[0] for x in res if bloqueado(x[2], x[3])]
                r["falsos_positivos"] = fp
            # Latencias
            asyncio.run(consultar_muchos(puerto, DOMINIOS_NORMALES))  # calentar caché
            r["latencia_cache_ms"] = percentiles([x[1] for x in asyncio.run(
                consultar_muchos(puerto, DOMINIOS_NORMALES * 10, concurrencia=4))])
            nuevas = [f"n{random.getrandbits(40):x}.prueba-{i % 97}.es" for i in range(1500)]
            r["latencia_consulta_nueva_ms"] = percentiles([x[1] for x in asyncio.run(
                consultar_muchos(puerto, nuevas, concurrencia=4))])
            if nombre != "sin bloqueador":
                r["latencia_bloqueado_ms"] = percentiles([x[1] for x in asyncio.run(
                    consultar_muchos(puerto, muestra_lista[:1000], concurrencia=4))])
            # Carga máxima
            open(f_nuevas, "w").write("".join(f"q{random.getrandbits(48):x}.carga.es A\n" for _ in range(200000)))
            r["carga_cache"] = dnsperf_qps(puerto, f_cache)
            r["carga_bloqueados"] = dnsperf_qps(puerto, f_bloq) if nombre != "sin bloqueador" else None
            r["carga_consultas_nuevas"] = dnsperf_qps(puerto, f_nuevas)
            r["memoria_rss_mb"] = round((rss_kb(pid) or 0) / 1024, 1)
            r["cpu_usada_s"] = round(cpu_seg(pid) - cpu0, 1)
            resultados[nombre] = r
            print(f"{nombre}: hecho", flush=True)
    finally:
        for p in procesos.values():
            p.terminate()
        origen.send_signal(signal.SIGTERM)
        for p in list(procesos.values()) + [origen]:
            try:
                p.wait(10)
            except subprocess.TimeoutExpired:
                p.kill()

    with open(os.path.join(a.salida, "resultados.json"), "w") as f:
        json.dump(resultados, f, indent=2, ensure_ascii=False)
    print(json.dumps(resultados, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
