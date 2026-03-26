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

## Parte 3 — Instalación base

### Paso 6: Clonar el repositorio

```bash
git clone https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64.git
cd tailscale-exit-node-arm64
```

### Paso 7: Ejecutar el script de instalación

```bash
bash scripts/install.sh
```

El script realiza automáticamente:
- Habilita el reenvío de paquetes IP (necesario para el exit node)
- Instala Tailscale
- Descarga el binario `picoclaw` desde GitHub
- Crea un usuario dedicado sin privilegios para el servicio
- Instala y activa `picoclaw` como servicio systemd

### Paso 8: Activar el nodo de salida en Tailscale

```bash
sudo tailscale up --advertise-exit-node
```

Abre el enlace que aparece en la terminal para autenticar la placa en tu cuenta de Tailscale.

### Paso 9: Aprobar el nodo en el panel de Tailscale

1. Ve a **https://login.tailscale.com/admin/machines**
2. Busca tu Raspberry Pi en la lista
3. Haz clic en `...` > **Edit route settings**
4. Activa **Use as exit node**

---

## Parte 4 — Verificación

### Comprobar el estado de todo el sistema de un vistazo

```bash
bash scripts/status.sh
```

Muestra el estado de IP forwarding, Tailscale, PicoClaw, AdGuard Home, ancho de banda, RAM, disco y temperatura.

### Verificar Tailscale

```bash
sudo tailscale status
```

Debes ver tu placa listada con la etiqueta `exit node`.

### Verificar PicoClaw

```bash
sudo systemctl status picoclaw.service
```

Debe mostrar `active (running)`. Si hay error:

```bash
sudo journalctl -u picoclaw.service -n 50
```

### Verificar el reenvío IP

```bash
sysctl net.ipv4.ip_forward        # Debe devolver: 1
sysctl net.ipv6.conf.all.forwarding  # Debe devolver: 1
```

---

## Parte 5 — Funciones opcionales

### Bloqueo de publicidad con AdGuard Home

Instala AdGuard Home y conéctalo a Tailscale MagicDNS para bloquear anuncios en todos tus dispositivos:

```bash
bash scripts/setup_adguard.sh
```

El script instala AdGuard Home y muestra los pasos para configurarlo con Tailscale. El panel web queda disponible en `http://<IP-de-la-placa>:3000`.

---

### Actualizaciones automáticas de PicoClaw

Activa una tarea cron que comprueba cada noche si hay una nueva versión y actualiza solo si hay cambios:

```bash
# Instalar (se ejecuta todos los días a las 04:00)
bash scripts/auto_update.sh --instalar-cron

# Desinstalar
bash scripts/auto_update.sh --desinstalar-cron
```

Los logs quedan en `/var/log/picoclaw_update.log`.

---

### Alertas vía Telegram

Recibe una notificación en tu móvil si PicoClaw o Tailscale caen, si se va la luz o si el disco está lleno.

**Paso 1:** Configura tu bot de Telegram:
1. Habla con **@BotFather** en Telegram y crea un bot → guarda el `TOKEN`
2. Habla con **@userinfobot** → guarda tu `CHAT_ID`

**Paso 2:** Edita el script con tus datos:

```bash
nano scripts/alertas.sh
```

Rellena las variables al inicio del archivo:
```bash
TELEGRAM_TOKEN="tu_token_aqui"
TELEGRAM_CHAT_ID="tu_chat_id_aqui"
```

**Paso 3:** Añade el script al cron para que se ejecute cada 5 minutos:

```bash
crontab -e
```

Añade esta línea al final:
```
*/5 * * * * /bin/bash /home/pi/tailscale-exit-node-arm64/scripts/alertas.sh
```

---

## Parte 6 — Mantenimiento

### Actualizar todos los componentes manualmente

```bash
bash scripts/update.sh
```

### Reiniciar servicios

```bash
sudo systemctl restart tailscaled
sudo systemctl restart picoclaw.service
```

### Ver logs en tiempo real

```bash
# Logs de PicoClaw
sudo journalctl -u picoclaw.service -f

# Logs de Tailscale
sudo journalctl -u tailscaled -f
```

### Desinstalar todo

```bash
bash scripts/uninstall.sh
```

---

## Resiliencia: IP dinámica y cortes de luz

- **IP dinámica:** Tailscale usa una red mesh basada en WireGuard. Si tu operador cambia tu IP pública, Tailscale renegocia la conexión automáticamente. No necesitas configurar puertos ni DDNS.
- **Cortes de luz:** Al volver la corriente, la Raspberry Pi arranca sola. Los servicios `tailscaled` y `picoclaw` están configurados en systemd para iniciarse automáticamente. El sistema queda operativo sin intervención manual.
