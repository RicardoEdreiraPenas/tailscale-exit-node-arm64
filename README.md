<div align="center">

# 🌐 Tailscale Exit Node ARM64

### Convierte tu Raspberry Pi en un nodo de salida VPN doméstico

*Navega desde cualquier lugar del mundo a través de tu IP residencial — automático, seguro y sin mantenimiento*

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
║                                                          ║
║   ├── 🔗 tailscaled    →  red mesh VPN                   ║
║   ├── 🚇 picoclaw      →  túnel residencial              ║
║   └── 🛡️ AdGuard Home  →  bloqueo de anuncios            ║
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

> 💡 El binario `picoclaw` se descarga automáticamente durante la instalación.

---

## 🚀 Instalación rápida

```bash
# 1️⃣  Clona el repositorio en la Raspberry Pi
git clone https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64.git
cd tailscale-exit-node-arm64

# 2️⃣  Ejecuta el instalador (descarga todo automáticamente)
bash scripts/install.sh

# 3️⃣  Autentica y activa el nodo de salida
sudo tailscale up --advertise-exit-node
```

> Tras el paso 3️⃣, abre el enlace que aparece en la terminal y aprueba el nodo en el panel de Tailscale.

<details>
<summary>📦 Descarga manual de PicoClaw (opcional)</summary>

```bash
wget https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw_linux_arm64 -O picoclaw
```

</details>

---

## 📱 Conectar tus dispositivos

| Dispositivo | Instalación | Pasos |
|:---:|:---:|:---|
| 🖥️ **Windows** | [Descargar](https://tailscale.com/download/windows) | Instala Tailscale → bandeja del sistema → **Exit Node** → selecciona la Raspberry Pi |
| 🍎 **Mac** | [App Store](https://apps.apple.com/app/tailscale/id1475387142) | Instala Tailscale → barra de menú → **Exit Node** → selecciona la Raspberry Pi |
| 📺 **Fire TV Stick** | Tienda Amazon | Busca *Tailscale* → instala → activa **Exit Node** en la app |
| 📱 **Android TV / Google TV** | Google Play | Busca *Tailscale* → instala → activa **Exit Node** en la app |
| 📺 **Smart TV Samsung / LG** | Sin app | Configura la Raspberry Pi como **gateway** en los ajustes de red del TV |

> 📖 Instrucciones detalladas para cada dispositivo en [GUIA_INSTALACION.md](GUIA_INSTALACION.md)

---

## 🧰 Scripts disponibles

### ⚙️ Instalación y mantenimiento

| Comando | Descripción |
|:---|:---|
| `bash scripts/install.sh` | ✅ Instalación completa: IP forwarding, Tailscale, PicoClaw y systemd |
| `bash scripts/update.sh` | 🔄 Actualiza Tailscale y PicoClaw manualmente |
| `bash scripts/uninstall.sh` | 🗑️ Desinstalación completa y limpieza del sistema |

### 📊 Monitorización

| Comando | Descripción |
|:---|:---|
| `bash scripts/status.sh` | 📋 Panel de estado: servicios, red, RAM, disco, temperatura y ancho de banda |

### 🌟 Funciones opcionales

| Comando | Descripción |
|:---|:---|
| `bash scripts/setup_adguard.sh` | 🛡️ Instala AdGuard Home con integración Tailscale MagicDNS |
| `bash scripts/auto_update.sh` | 🤖 Comprueba y aplica actualizaciones de PicoClaw por hash MD5 |
| `bash scripts/auto_update.sh --instalar-cron` | ⏰ Programa la actualización automática diaria a las 04:00 |
| `bash scripts/auto_update.sh --desinstalar-cron` | ❌ Elimina la tarea cron de actualización automática |
| `bash scripts/alertas.sh` | 📬 Monitoriza servicios y envía alertas vía Telegram |

---

## 📁 Estructura del repositorio

```
tailscale-exit-node-arm64/
│
├── 📁 config/
│   └── picoclaw.service      # Servicio systemd (usuario sin privilegios)
│
├── 📁 scripts/
│   ├── install.sh            # ✅ Instalador automático
│   ├── uninstall.sh          # 🗑️ Desinstalación completa
│   ├── update.sh             # 🔄 Actualizador manual
│   ├── status.sh             # 📋 Panel de estado
│   ├── setup_adguard.sh      # 🛡️ Instalador de AdGuard Home
│   ├── auto_update.sh        # 🤖 Actualización automática con cron
│   └── alertas.sh            # 📬 Alertas vía Telegram
│
├── 📄 GUIA_INSTALACION.md    # Guía paso a paso desde cero
└── 📄 README.md
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

- 🔐 El servicio `picoclaw` corre bajo un **usuario dedicado sin shell ni privilegios** (`NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`)
- 📦 El binario `picoclaw` **no se incluye en el repositorio** y se descarga siempre desde la release oficial de GitHub
- 🚫 Excluido en `.gitignore` para evitar subidas accidentales

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
| 7️⃣ | Conexión de dispositivos: Windows, Mac, Fire TV Stick, Android TV, Smart TV |
| 8️⃣ | Solución de problemas frecuentes |

---

## 🗺️ Roadmap

- [x] 🛡️ **Bloqueo de publicidad (DNS):** AdGuard Home con integración Tailscale MagicDNS
- [x] 📊 **Monitorización de ancho de banda:** vnStat integrado en el panel de estado
- [x] 🤖 **Actualizaciones automáticas:** Cron con detección de cambios por hash MD5
- [x] 📬 **Sistema de alertas:** Notificaciones vía Telegram para caída de servicios, temperatura y disco

> 💬 Las contribuciones (Pull Requests) con nuevas ideas son siempre bienvenidas.

---

<div align="center">

Hecho con ❤️ para la comunidad · [GUIA_INSTALACION.md](GUIA_INSTALACION.md) · [Reportar un problema](https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64/issues)

</div>
