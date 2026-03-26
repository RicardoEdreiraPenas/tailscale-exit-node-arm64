# Guía de Instalación: Tailscale Exit Node + PicoClaw en Raspberry Pi

Guía completa paso a paso para configurar una Raspberry Pi (o Radxa ROCK 3C) como nodo de salida VPN doméstico.

---

## Requisitos

- Raspberry Pi 4, 5 o Radxa ROCK 3C
- Tarjeta microSD de 8 GB o más
- Ordenador con Windows o macOS para preparar la microSD
- Conexión a internet

---

## Parte 1 — Preparar la microSD (desde tu ordenador)

### Paso 1: Descargar Raspberry Pi Imager

Descarga e instala la herramienta oficial desde:
**https://www.raspberrypi.com/software/**

### Paso 2: Grabar el sistema operativo

1. Abre **Raspberry Pi Imager**
2. **Elegir Dispositivo:** selecciona tu modelo (Raspberry Pi 4 o 5)
3. **Elegir Sistema Operativo:**
   - Ve a `Raspberry Pi OS (Other)`
   - Selecciona **Raspberry Pi OS Lite (64-bit)**

   > **Importante:** debe ser 64-bit (ARM64). La versión Lite no tiene escritorio, lo que ahorra recursos para el túnel.

4. **Elegir Almacenamiento:** selecciona tu tarjeta microSD
5. Haz clic en **Editar ajustes** (icono del engranaje) y configura:
   - **SSH:** habilitar con autenticación por contraseña
   - **Usuario:** ej. `pi` con una contraseña segura
   - **Wi-Fi:** introduce tu SSID y contraseña
   - **Zona horaria:** ajusta a tu región
6. Guarda y haz clic en **Escribir**. Espera a que termine.

---

## Parte 2 — Primer arranque y conexión SSH

### Paso 3: Arrancar la Raspberry Pi

1. Saca la microSD del ordenador e insértala en la Raspberry Pi
2. Conecta la alimentación y espera ~2 minutos a que arranque

### Paso 4: Conectarse por SSH

Desde la terminal de tu ordenador (PowerShell en Windows, Terminal en Mac):

```bash
ssh pi@raspberrypi.local
```

> Si `raspberrypi.local` no responde, busca la IP en tu router y conéctate así:
> ```bash
> ssh pi@192.168.1.XXX
> ```

### Paso 5: Actualizar el sistema

Una vez dentro de la Raspberry Pi, actualiza los paquetes:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Parte 3 — Instalación automática

### Paso 6: Clonar el repositorio

```bash
git clone https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64.git
cd tailscale-exit-node-arm64
```

### Paso 7: Ejecutar el script de instalación

El script instala Tailscale, descarga PicoClaw y configura ambos servicios automáticamente:

```bash
bash scripts/install.sh
```

Lo que hace el script:
- Habilita el reenvío de paquetes IP (necesario para el exit node)
- Instala Tailscale si no está instalado
- Descarga el binario `picoclaw` desde GitHub
- Instala y activa el servicio `picoclaw` en systemd

### Paso 8: Activar el nodo de salida en Tailscale

```bash
sudo tailscale up --advertise-exit-node
```

Esto abrirá un enlace en la terminal. Ábrelo en el navegador para autenticar la placa en tu cuenta de Tailscale.

### Paso 9: Aprobar el nodo de salida en el panel de Tailscale

1. Ve a **https://login.tailscale.com/admin/machines**
2. Busca tu Raspberry Pi en la lista
3. Haz clic en los tres puntos `...` > **Edit route settings**
4. Activa **Use as exit node**

---

## Parte 4 — Verificación

### Comprobar que Tailscale está activo

```bash
sudo tailscale status
```

Debes ver tu placa listada con la etiqueta `exit node`.

### Comprobar que PicoClaw está corriendo

```bash
sudo systemctl status picoclaw.service
```

La salida debe mostrar `active (running)`. Si hay algún error:

```bash
# Ver los últimos logs del servicio
sudo journalctl -u picoclaw.service -n 50
```

### Comprobar el reenvío IP

```bash
sysctl net.ipv4.ip_forward
# Debe devolver: net.ipv4.ip_forward = 1

sysctl net.ipv6.conf.all.forwarding
# Debe devolver: net.ipv6.conf.all.forwarding = 1
```

---

## Parte 5 — Comandos útiles de mantenimiento

### Reiniciar servicios

```bash
sudo systemctl restart tailscaled
sudo systemctl restart picoclaw.service
```

### Detener servicios

```bash
sudo systemctl stop picoclaw.service
sudo systemctl stop tailscaled
```

### Ver estado general del sistema

```bash
# Uso de memoria y CPU
htop

# Espacio en disco
df -h

# Temperatura de la placa
vcgencmd measure_temp
```

### Actualizar Tailscale

```bash
sudo apt update && sudo apt upgrade tailscale -y
sudo systemctl restart tailscaled
```

---

## Resiliencia: IP dinámica y cortes de luz

- **IP dinámica:** Tailscale usa una red mesh basada en WireGuard. Si tu operador cambia tu IP pública, Tailscale renegocia la conexión automáticamente. No necesitas configurar puertos ni DDNS.

- **Cortes de luz:** Al volver la corriente, la Raspberry Pi arranca sola. Los servicios `tailscaled` y `picoclaw` están configurados en systemd para iniciarse automáticamente. El sistema queda operativo sin intervención manual.
