# AdGuard Home frente a Pi-hole: comparación en laboratorio

Prueba hecha el 30/10/2026 con `comparar.py` sobre un servidor x86 (Intel Xeon a
2,1 GHz), con los dos bloqueadores limitados a **un solo núcleo** para acercarse
a una Raspberry Pi. Los números absolutos serán más bajos en la placa; lo que
interesa es la comparación y el orden de magnitud. Para medir en la Raspberry
real, usa `pruebas/benchmark_pi.sh`.

## Condiciones

| | |
|---|---|
| Versiones | AdGuard Home v0.107.79, Pi-hole FTL v6.8 (binarios oficiales, sumas verificadas) |
| Configuración | la de este repositorio (`config/plantillas/`) |
| Lista de bloqueo | la misma para los dos: StevenBlack hosts, 76.736 dominios |
| DNS de origen | simulado en local con 20 ms de retardo, como un proveedor real |
| Prueba de anuncios | 131 dominios de publicidad y rastreo de la prueba de d3ward (independiente de la lista) |
| Webs normales | 93 dominios habituales en España (bancos, prensa, administración, tiendas…) |

## Resultados

| | AdGuard Home | Pi-hole | Sin bloqueador |
|---|---|---|---|
| Dominios de la lista bloqueados | 2000/2000 | 2000/2000 | — |
| Prueba de anuncios bloqueados | 89/131 | 89/131 | — |
| Falsos positivos en webs normales | 0/93 | 0/93 | — |
| Respuesta en caché (p50 / p99) | 0,18 / 1,39 ms | 0,22 / 0,47 ms | 20,5 ms (siempre sale) |
| Consulta nueva (p50 / p99) | 20,95 / 22,28 ms | 21,11 / 25,04 ms | 20,54 / 22,89 ms |
| Dominio bloqueado (p50) | 0,20 ms | 0,23 ms | — |
| Carga máxima, respuestas en caché | 17.600 consultas/s | 27.250 consultas/s | — |
| Carga máxima, consultas nuevas | 8.670/s sin errores | 2.020/s, 9 % rechazadas | — |
| Memoria (RSS) | 145 MB | 277 MB¹ | — |

¹ Incluye la memoria compartida donde Pi-hole guarda el historial de consultas de las
últimas 24 horas; crece con el uso.

## Qué significa

- **Bloquean exactamente lo mismo** con la misma lista. La diferencia de eficacia
  depende de las listas que elijas, no del programa. Los 42 dominios de la prueba
  que no se bloquean no están en la lista StevenBlack; se pueden añadir más listas
  en cualquiera de los dos.
- **Velocidad percibida: empate.** Una vez en caché, los dos responden en unas
  décimas de milisegundo, 100 veces más rápido que ir al proveedor (20 ms). Una
  consulta nueva añade menos de 1 ms. Ninguna persona nota esa diferencia.
- **Ninguno frena la conexión.** El bloqueador solo interviene en la consulta DNS,
  no en la descarga, el streaming ni las videollamadas. Al quitar anuncios, las
  webs suelen cargar antes.
- **Bajo carga extrema** Pi-hole sirve más consultas por segundo desde caché, y
  AdGuard aguanta mejor una avalancha de consultas nuevas. Una casa genera decenas
  de consultas por segundo, muy lejos de cualquiera de los dos límites.

## Diferencias que sí importan para este proyecto

| | AdGuard Home | Pi-hole |
|---|---|---|
| Consultas hacia fuera | cifradas (DNS sobre HTTPS): tu operador no ve qué webs visitas | sin cifrar, salvo que añadas unbound o cloudflared |
| Validación DNSSEC | no la hace (la delega en Quad9/Cloudflare) | la hace en local (añade algo de latencia en consultas nuevas) |
| Instalación | un único programa, verificado con su suma SHA-256 | instalador oficial verificado, que clona repositorios y descarga su motor |
| Límite por cliente | desactivado en esta configuración | 1000 consultas/min por dispositivo (de fábrica) |

**Recomendación para este proyecto: AdGuard Home**, por el cifrado de las consultas
y porque es más sencillo de mantener. Pi-hole es igual de válido si prefieres su panel.

## Incidencias de la prueba (y cómo se resolvieron)

1. Con la validación DNSSEC activa, Pi-hole rechazaba todas las respuestas del
   origen simulado, que no está firmado. En el laboratorio se desactiva en los dos.
2. El límite de fábrica de Pi-hole (1000 consultas/min por cliente) rechazaba la
   prueba, que sale toda de 127.0.0.1. Se desactivó para medir lo mismo que en
   AdGuard. En casa cada dispositivo tiene su propia IP y no se alcanza.
3. El medidor contaba al principio las respuestas rechazadas como rápidas. Ahora
   solo cuenta NOERROR y NXDOMAIN; el resto se registra como error.

Datos completos en `resultados.json`.
