# Tailscale Exit Node ARM64

Convierte una **Raspberry Pi** o **Radxa ROCK 3C** en un nodo de salida VPN doméstico usando Tailscale + PicoClaw. Tus dispositivos remotos (TV Sticks, móviles, etc.) navegan a través de tu IP residencial de forma automática y sin mantenimiento.

---

## Como funciona

```
TV Stick / Dispositivo remoto
        │
        │  VPN Tailscale (WireGuard)
        ▼
 Raspberry Pi (Exit Node)
        │
        ├── tailscaled   →  gestiona la red mesh VPN
        └── picoclaw     →  túnel residencial
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

# 2. Ejecuta el instalador (descarga picoclaw, instala Tailscale y configura los servicios)
bash scripts/install.sh

# 3. Autentica y activa el nodo de salida
sudo tailscale up --advertise-exit-node
```

Tras el paso 3 abre el enlace que aparece en la terminal, aprueba el nodo en el panel de Tailscale y listo.

> **Descarga manual de PicoClaw (opcional):**
> ```bash
> wget https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw_linux_arm64 -O picoclaw
> ```

---

## Scripts

| Comando | Descripción |
|---|---|
| `bash scripts/install.sh` | Instalación completa (IP forwarding, Tailscale, PicoClaw, systemd) |
| `bash scripts/status.sh` | Panel de estado: servicios, red, RAM, disco y temperatura |
| `bash scripts/update.sh` | Actualiza Tailscale y PicoClaw a la última versión |
| `bash scripts/uninstall.sh` | Desinstalación completa y limpieza del sistema |

---

## Estructura del repositorio

```
tailscale-exit-node-arm64/
├── config/
│   └── picoclaw.service      # Servicio systemd (usuario sin privilegios)
├── scripts/
│   ├── install.sh            # Instalador automático
│   ├── uninstall.sh          # Desinstalación completa
│   ├── update.sh             # Actualizador de componentes
│   └── status.sh             # Panel de estado del sistema
├── GUIA_INSTALACION.md       # Guía paso a paso desde cero (Windows/Mac)
└── README.md
```

---

## Resiliencia

- **IP dinámica:** Tailscale usa una red mesh basada en WireGuard. Si tu operador cambia tu IP pública, las conexiones se renegocian de forma automática. Sin DDNS, sin reenvío de puertos.
- **Cortes de luz:** Al recuperarse la corriente, la Raspberry Pi arranca y los servicios `tailscaled` y `picoclaw` se inician solos gracias a systemd. Sin intervención manual.

---

## Seguridad

- El servicio `picoclaw` corre bajo un usuario dedicado sin shell ni privilegios (`NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`).
- El binario `picoclaw` no se incluye en el repositorio (excluido en `.gitignore`) y se descarga siempre desde la release oficial de GitHub.

---

## Guía completa

Para preparar la microSD desde cero en Windows o Mac consulta [GUIA_INSTALACION.md](GUIA_INSTALACION.md).
