# Tailscale Exit Node ARM64

Convierte una **Raspberry Pi** o **Radxa ROCK 3C** en un nodo de salida VPN doméstico usando Tailscale + PicoClaw. Tus dispositivos remotos (TV Sticks, móviles, etc.) navegan a través de tu IP residencial de forma automática y sin mantenimiento.

---

## Cómo funciona

```
TV Stick / Dispositivo remoto
        │
        │  VPN Tailscale (WireGuard)
        ▼
 Raspberry Pi (Exit Node)
        │
        ├── tailscaled       →  gestiona la red mesh VPN
        ├── picoclaw         →  túnel residencial
        └── AdGuard Home     →  bloqueo de anuncios (opcional)
        │
        ▼
  Tu conexión a internet doméstica
```

---

## Requisitos

| Hardware | Software |
|---|---|
| Raspberry Pi 4, 5 o Radxa ROCK 3C | Raspberry Pi OS Lite 64-bit (ARM64) |
| Tarjeta microSD 8 GB o más | Cuenta gratuita en [tailscale.com](https://tailscale.com) |

> El binario `picoclaw` se descarga automáticamente durante la instalación.

---

## Instalación rápida

```bash
# 1. Clona el repositorio en la Raspberry Pi
git clone https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64.git
cd tailscale-exit-node-arm64

# 2. Ejecuta el instalador
bash scripts/install.sh

# 3. Autentica y activa el nodo de salida
sudo tailscale up --advertise-exit-node
```

Tras el paso 3, abre el enlace que aparece en la terminal y aprueba el nodo en el panel de Tailscale.

> **Descarga manual de PicoClaw (opcional):**
> ```bash
> wget https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw_linux_arm64 -O picoclaw
> ```

---

## Scripts

### Instalación y mantenimiento

| Comando | Descripción |
|---|---|
| `bash scripts/install.sh` | Instalación completa: IP forwarding, Tailscale, PicoClaw y systemd |
| `bash scripts/update.sh` | Actualiza Tailscale y PicoClaw a la última versión manualmente |
| `bash scripts/uninstall.sh` | Desinstalación completa y limpieza del sistema |

### Monitorización

| Comando | Descripción |
|---|---|
| `bash scripts/status.sh` | Panel de estado: servicios, red, RAM, disco, temperatura y ancho de banda |

### Funciones opcionales

| Comando | Descripción |
|---|---|
| `bash scripts/setup_adguard.sh` | Instala AdGuard Home con integración Tailscale MagicDNS |
| `bash scripts/auto_update.sh` | Comprueba y aplica actualizaciones de PicoClaw por hash MD5 |
| `bash scripts/auto_update.sh --instalar-cron` | Programa la actualización automática diaria a las 04:00 |
| `bash scripts/auto_update.sh --desinstalar-cron` | Elimina la tarea cron de actualización automática |
| `bash scripts/alertas.sh` | Monitoriza servicios y envía alertas vía Telegram |

---

## Estructura del repositorio

```
tailscale-exit-node-arm64/
├── config/
│   └── picoclaw.service      # Servicio systemd (usuario sin privilegios)
├── scripts/
│   ├── install.sh            # Instalador automático
│   ├── uninstall.sh          # Desinstalación completa
│   ├── update.sh             # Actualizador manual de componentes
│   ├── status.sh             # Panel de estado del sistema
│   ├── setup_adguard.sh      # Instalador de AdGuard Home
│   ├── auto_update.sh        # Actualización automática con cron
│   └── alertas.sh            # Alertas vía Telegram
├── GUIA_INSTALACION.md       # Guía paso a paso desde cero (Windows/Mac)
└── README.md
```

---

## Resiliencia

- **IP dinámica:** Tailscale usa una red mesh basada en WireGuard. Si tu operador cambia tu IP pública, las conexiones se renegocian automáticamente. Sin DDNS, sin reenvío de puertos.
- **Cortes de luz:** Al recuperarse la corriente, la Raspberry Pi arranca y los servicios `tailscaled` y `picoclaw` se inician solos gracias a systemd. Sin intervención manual.

---

## Seguridad

- El servicio `picoclaw` corre bajo un usuario dedicado sin shell ni privilegios (`NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`).
- El binario `picoclaw` no se incluye en el repositorio (excluido en `.gitignore`) y se descarga siempre desde la release oficial de GitHub.

---

## Guía completa

Consulta [GUIA_INSTALACION.md](GUIA_INSTALACION.md) para instrucciones detalladas que incluyen:

- Preparación de la microSD desde Windows o Mac
- Instalación y verificación paso a paso
- Configuración de funciones opcionales (AdGuard, alertas, auto-update)
- **Cómo conectar cada dispositivo:** Windows, Mac, Fire TV Stick, Android TV y Smart TV Samsung/LG
- Solución de problemas frecuentes

---

## Roadmap

- [x] **Bloqueo de publicidad (DNS):** AdGuard Home con integración Tailscale MagicDNS — `bash scripts/setup_adguard.sh`
- [x] **Monitorización de ancho de banda:** vnStat integrado en el panel de estado — `bash scripts/status.sh`
- [x] **Actualizaciones automáticas:** Cron con detección de cambios por hash MD5 — `bash scripts/auto_update.sh --instalar-cron`
- [x] **Sistema de alertas:** Notificaciones vía Telegram para caída de servicios, temperatura y disco — `bash scripts/alertas.sh`

Las contribuciones (Pull Requests) con nuevas ideas son siempre bienvenidas.
