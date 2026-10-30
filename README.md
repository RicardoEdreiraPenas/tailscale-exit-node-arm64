<div align="center">

# 🌐 Tailscale Exit Node ARM64

### Convierte tu Raspberry Pi en un nodo de salida VPN doméstico

*Navega desde cualquier sitio con la IP de tu casa: cifrado, sin abrir puertos y con actualizaciones automáticas*

<img width="2752" height="1536" alt="image" src="https://github.com/user-attachments/assets/6f0b06b6-763a-4f96-b389-aa7ec38db590" />

---

[![Tailscale](https://img.shields.io/badge/Tailscale-WireGuard-blue?style=for-the-badge&logo=wireguard&logoColor=white)](https://tailscale.com)
[![Platform](https://img.shields.io/badge/Platform-ARM64-green?style=for-the-badge&logo=raspberrypi&logoColor=white)](https://www.raspberrypi.com)
[![OS](https://img.shields.io/badge/OS-Raspberry%20Pi%20OS%20Lite-red?style=for-the-badge&logo=linux&logoColor=white)](https://www.raspberrypi.com/software/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)

---

**📺 Fire TV Stick &nbsp;·&nbsp; 🖥️ Windows &nbsp;·&nbsp; 🍎 Mac &nbsp;·&nbsp; 📱 Android TV &nbsp;·&nbsp; 📺 Smart TV**

</div>

---

## ⚡ ¿Cómo funciona?

```
╔══════════════════════════════════════════════════════════╗
║         TUS DISPOSITIVOS (en cualquier lugar)            ║
║   📺 Fire TV Stick  🖥️ Windows  🍎 Mac  📱 Android TV   ║
╚═══════════════════════╦══════════════════════════════════╝
                        ║
                        ║  🔒 VPN Tailscale (WireGuard)
                        ▼
╔══════════════════════════════════════════════════════════╗
║              🍓 RASPBERRY PI  (tu casa)                  ║
║   ├── 🔗 tailscaled    →  red mesh VPN (WireGuard)       ║
║   ├── 🧱 ufw           →  entrada cerrada                ║
║   ├── 🛡️ AdGuard/Pi-hole → bloqueo de anuncios (opcional)║
║   └── 🤖 picoclaw      →  estado por Telegram (opcional) ║
╚═══════════════════════╦══════════════════════════════════╝
                        ║
                        ▼
              🌍 Tu IP doméstica
```

---

## 🛠️ Requisitos

| 🔧 Hardware | 💾 Software |
|:---:|:---:|
| Raspberry Pi 4, 5 o Radxa ROCK 3C | Raspberry Pi OS Lite **64-bit (ARM64)** |
| Tarjeta microSD 8 GB o más | Cuenta gratuita en [tailscale.com](https://tailscale.com) |

> 💡 Todo lo que se descarga se comprueba con su suma SHA-256 antes de instalarse (`versiones.conf`).

---

## 🚀 Instalación rápida

```bash
# 1️⃣  Clona el repositorio en la Raspberry Pi
git clone https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64.git
cd tailscale-exit-node-arm64

# 2️⃣  Instala (bloqueador: adguard, pihole o ninguno)
sudo bash scripts/install.sh --bloqueador=adguard

# 3️⃣  Autentica y activa el nodo de salida
sudo tailscale up --advertise-exit-node

# 4️⃣  Comprueba que todo está en verde
sudo bash scripts/status.sh
```

> Tras el paso 3️⃣, abre el enlace que aparece en la terminal y aprueba el nodo en el panel de Tailscale (**Edit route settings → Use as exit node**).

> ¿Venías de una versión anterior? Ejecuta el instalador igual: detecta el servicio antiguo de PicoClaw y la tarea cron de actualización, los desactiva y te dice cómo seguir.

---

## 📱 Conectar tus dispositivos

| Dispositivo | Instalación | Pasos |
|:---:|:---:|:---|
| 🖥️ **Windows** | [Descargar](https://tailscale.com/download/windows) | Instala Tailscale → bandeja del sistema → **Exit Node** → selecciona la Raspberry Pi |
| 🍎 **Mac** | [App Store](https://apps.apple.com/app/tailscale/id1475387142) | Instala Tailscale → barra de menú → **Exit Node** → selecciona la Raspberry Pi |
| 📺 **Fire TV Stick** | APK directo | Activa opciones de desarrollador → instala **Downloader** → descarga desde `pkgs.tailscale.com/stable` → escanea QR → activa **Exit Node** |
| 📱 **Android TV / Google TV** | Google Play | Busca *Tailscale* → instala → activa **Exit Node** en la app |
| 📺 **Smart TV Samsung / LG** | Sin app | Usa un Chromecast/Fire TV con Tailscale o un router de viaje con Tailscale ([ver guía](GUIA_INSTALACION.md#smart-tv-samsung-o-lg-sin-tailscale)) |

> 📖 Instrucciones detalladas para cada dispositivo en [GUIA_INSTALACION.md](GUIA_INSTALACION.md)

---

## 🧰 Scripts disponibles

Todos se ejecutan con `sudo bash scripts/<nombre>`.

| Comando | Descripción |
|:---|:---|
| `install.sh` | ✅ Instalación completa: reenvío, Tailscale firmado, rendimiento, cortafuegos y actualizaciones automáticas |
| `status.sh` | 📋 Panel de estado: Tailscale, exit node, cortafuegos, SSH, bloqueador, temperatura, memoria y disco |
| `bloqueador.sh instalar adguard\|pihole` | 🛡️ Bloqueo de anuncios por DNS (uno de los dos) |
| `endurecer_ssh.sh` | 🔐 SSH solo con clave, comprobando antes que la tuya funciona |
| `alertas.sh --configurar` | 📬 Avisos por Telegram si algo se cae |
| `picoclaw.sh instalar` | 🤖 Asistente de estado por Telegram, sin acceso a la shell ([guía](GUIA_PICOCLAW_IA.md)) |
| `update.sh` | 🔄 Aplica al momento las versiones fijadas en `versiones.conf` |
| `uninstall.sh` | 🗑️ Deshace la instalación |

> Opción `--simular` en `install.sh`: muestra lo que haría sin cambiar nada.

---

## 📁 Estructura del repositorio

```
tailscale-exit-node-arm64/
├── versiones.conf            # Versiones fijadas y sus sumas SHA-256
├── scripts/                  # Instalación, estado, bloqueador, alertas, PicoClaw, SSH
│   └── lib/comun.sh          # Funciones compartidas (descarga verificada, cortafuegos…)
├── config/
│   ├── systemd/              # Servicios aislados (usuario propio, sin privilegios)
│   └── plantillas/           # Configuración inicial de AdGuard, Pi-hole y PicoClaw
├── pruebas/
│   ├── laboratorio_dns/      # Comparación medida AdGuard vs Pi-hole
│   ├── benchmark_pi.sh       # Mediciones en la Raspberry real
│   └── velocidad_cliente.sh  # Velocidad con y sin exit node desde tu Mac/Linux
├── tests/                    # Pruebas automáticas (bats + Python) que corren en GitHub Actions
├── GUIA_INSTALACION.md
├── GUIA_PICOCLAW_IA.md
└── SECURITY.md
```

---

## ⚡ Resiliencia

<table>
<tr>
<td width="50%">

### 🌍 IP Dinámica
Tailscale usa una red **mesh basada en WireGuard**. Si tu operador cambia tu IP pública, las conexiones se renegocian automáticamente.

❌ Sin DDNS
❌ Sin reenvío de puertos
✅ Funciona solo

</td>
<td width="50%">

### 💡 Cortes de Luz
Al recuperarse la corriente, la Raspberry Pi arranca y los servicios se inician solos gracias a **systemd**.

❌ Sin intervención manual
✅ Recuperación automática
✅ Mantenimiento cero

</td>
</tr>
</table>

---

## 🔒 Seguridad

- 🔏 **Descargas verificadas:** AdGuard, el instalador de Pi-hole y PicoClaw se comprueban con SHA-256; la clave de Tailscale, por su huella.
- 🧱 **Cortafuegos:** entrada cerrada salvo SSH desde casa y Tailscale; los paneles web solo por Tailscale.
- 👤 **Servicios aislados:** cada uno con su usuario y restricciones de systemd; ninguno corre como root.
- 🤖 **PicoClaw sin shell:** solo lee un informe de estado y solo responde a tu ID de Telegram (tiene una vulnerabilidad de inyección de comandos sin parche).
- 🔄 **Parches automáticos** del sistema y de Tailscale cada día.

Detalles y modelo de amenazas en [SECURITY.md](SECURITY.md).

---

## 📊 ¿AdGuard o Pi-hole? ¿Frena la conexión?

Medido con los programas reales en [pruebas/laboratorio_dns](pruebas/laboratorio_dns/RESULTADOS.md): bloquean lo mismo con la misma lista, responden desde caché en ~0,2 ms y añaden menos de 1 ms a una consulta nueva. **Ninguno frena la conexión**, porque solo intervienen en la consulta DNS. Se recomienda AdGuard porque cifra las consultas hacia fuera.

---

## 📖 Guía completa

[GUIA_INSTALACION.md](GUIA_INSTALACION.md) cubre todo desde cero:

| # | Sección |
|:---:|:---|
| 1️⃣ | Preparar la microSD desde Windows o Mac |
| 2️⃣ | Primer arranque y conexión SSH |
| 3️⃣ | Instalación automática paso a paso |
| 4️⃣ | Verificación del sistema |
| 5️⃣ | Funciones opcionales: AdGuard Home, alertas Telegram, auto-update |
| 6️⃣ | Mantenimiento y comandos útiles |
| 7️⃣ | Prueba definitiva desde el móvil |
| 8️⃣ | Conexión de dispositivos: Windows, Mac, Fire TV Stick, Android TV, Smart TV |
| 9️⃣ | Solución de problemas frecuentes |

---

## 🗺️ Roadmap

- [x] 🛡️ Bloqueo de anuncios: AdGuard Home o Pi-hole, con comparación medida
- [x] 🔏 Descargas verificadas y versiones fijadas
- [x] 🧱 Cortafuegos y SSH solo con clave
- [x] 🚀 UDP GRO forwarding para más caudal con menos CPU
- [x] 🔄 Actualizaciones automáticas firmadas (sustituye al antiguo cron sin verificar)
- [x] 📬 Alertas por Telegram con el token protegido
- [x] 🧪 Pruebas automáticas en GitHub Actions
- [ ] 📈 Resultados de `benchmark_pi.sh` en una Raspberry Pi 4 y 5

---

<div align="center">

[GUIA_INSTALACION.md](GUIA_INSTALACION.md) · [SECURITY.md](SECURITY.md) · [Reportar un problema](https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64/issues)

</div>
