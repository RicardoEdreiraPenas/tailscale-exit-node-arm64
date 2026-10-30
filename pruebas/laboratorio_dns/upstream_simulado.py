#!/usr/bin/env python3
"""Servidor DNS de origen simulado para comparar bloqueadores en igualdad de condiciones.

Responde a cualquier consulta A con una IP de documentación (203.0.113.x) tras un
retardo fijo que imita al proveedor real (por defecto 20 ms). Las consultas AAAA y
del resto de tipos reciben una respuesta vacía. Cuenta las consultas que recibe, para
saber cuántas resuelve cada bloqueador desde su caché sin salir a internet.

Uso: python3 upstream_simulado.py --puerto 5300 --retardo-ms 20
"""

import argparse
import asyncio
import hashlib
import signal
import struct
import sys


def nombre_consultado(datos):
    i, partes = 12, []
    while datos[i] != 0:
        n = datos[i]
        partes.append(datos[i + 1:i + 1 + n].decode("ascii", "replace"))
        i += n + 1
    return ".".join(partes), i + 1


def responder(consulta):
    ident, flags, qd = struct.unpack("!HHH", consulta[:6])
    nombre, fin = nombre_consultado(consulta)
    qtype = struct.unpack("!H", consulta[fin:fin + 2])[0]
    pregunta = consulta[12:fin + 4]
    rd = flags & 0x0100
    cabecera_flags = 0x8000 | 0x0080 | rd  # QR, RA, copia RD
    if qtype == 1:  # A
        h = hashlib.sha256(nombre.encode()).digest()
        ip = bytes([203, 0, 113, 1 + h[0] % 250])
        rr = struct.pack("!HHHIH", 0xC00C, 1, 1, 300, 4) + ip
        return struct.pack("!HHHHHH", ident, cabecera_flags, 1, 1, 0, 0) + pregunta + rr
    return struct.pack("!HHHHHH", ident, cabecera_flags, 1, 0, 0, 0) + pregunta


class Protocolo(asyncio.DatagramProtocol):
    def __init__(self, retardo):
        self.retardo = retardo
        self.recibidas = 0

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        self.recibidas += 1
        try:
            r = responder(data)
        except Exception:
            return
        asyncio.get_running_loop().call_later(self.retardo, self.transport.sendto, r, addr)


async def principal(a):
    loop = asyncio.get_running_loop()
    _, proto = await loop.create_datagram_endpoint(
        lambda: Protocolo(a.retardo_ms / 1000), local_addr=(a.ip, a.puerto))
    parar = asyncio.Event()
    loop.add_signal_handler(signal.SIGTERM, parar.set)
    loop.add_signal_handler(signal.SIGUSR1, lambda: print(f"recibidas={proto.recibidas}", flush=True))
    print(f"upstream simulado en {a.ip}:{a.puerto} con {a.retardo_ms} ms", flush=True)
    await parar.wait()
    print(f"recibidas={proto.recibidas}", flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--ip", default="127.0.0.1")
    p.add_argument("--puerto", type=int, default=5300)
    p.add_argument("--retardo-ms", type=float, default=20)
    sys.exit(asyncio.run(principal(p.parse_args())))
