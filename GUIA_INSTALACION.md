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
   - <img width="1226" height="332" alt="image" src="https://github.com/user-attachments/assets/90f81daa-5987-4478-9664-d3d2ebf70397" />
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

## Parte 7 — Conectar tus dispositivos al Exit Node

Una vez la Raspberry Pi está configurada, conecta tus dispositivos instalando Tailscale en cada uno y seleccionando tu placa como nodo de salida.

---

### Windows (PC)

1. Descarga e instala Tailscale desde **https://tailscale.com/download/windows**
2. Inicia sesión con la misma cuenta que usaste en la Raspberry Pi
3. Haz clic en el icono de Tailscale en la barra de tareas (esquina inferior derecha)
4. Ve a **Exit Node** > selecciona tu Raspberry Pi de la lista
5. Listo. Todo el tráfico sale por tu IP doméstica.

> Para verificar que funciona, abre **https://whatismyip.com** — debe mostrar la IP de tu casa.

---

### Mac

1. Descarga e instala Tailscale desde la **App Store** (busca "Tailscale") o desde **https://tailscale.com/download/mac**
2. Inicia sesión con tu cuenta de Tailscale
3. Haz clic en el icono de Tailscale en la barra de menú (parte superior derecha)
4. Ve a **Exit Node** > selecciona tu Raspberry Pi
5. Listo.

> Para verificar, abre **https://whatismyip.com** en Safari o Chrome.

---

### Fire TV Stick (Amazon)

Tailscale tiene app oficial para Fire TV Stick.

1. En tu Fire TV Stick, ve a la **tienda de aplicaciones**
2. Busca **Tailscale** e instálala
3. Abre Tailscale e inicia sesión con tu cuenta
4. Una vez conectado, pulsa el botón de menú de la app
5. Selecciona **Use exit node** > elige tu Raspberry Pi
6. Listo. El streaming saldrá por tu IP doméstica.

> Si no encuentras Tailscale en la tienda, activa **"Aplicaciones de fuentes desconocidas"** en Configuración > Mi Fire TV > Opciones para desarrolladores, y descárgala desde el navegador Silk.

---

### Android TV / Google TV

1. En el Google Play Store de tu TV, busca **Tailscale** e instálala
2. Inicia sesión con tu cuenta
3. En la app, activa la conexión y selecciona tu Raspberry Pi como **Exit Node**
4. Listo.

> Compatible con: Chromecast con Google TV, NVIDIA Shield, televisores Sony, TCL, Hisense con Android TV, etc.

---

### Smart TV (sin Android TV — Samsung Tizen, LG webOS)

Los Smart TV de Samsung y LG **no tienen tienda de apps compatible con Tailscale**. La solución es configurar la Raspberry Pi como **router de salida** para toda la red local o usar un router con Tailscale.

**Opción recomendada — Configurar la Raspberry Pi como gateway:**

En la Raspberry Pi, activa el enrutamiento para tu red local:

```bash
# Anuncia el rango de tu red local (ajusta según tu router, normalmente 192.168.1.0/24)
sudo tailscale up --advertise-exit-node --advertise-routes=192.168.1.0/24
```

Luego en el panel de Tailscale aprueba también las rutas:
1. Ve a **https://login.tailscale.com/admin/machines**
2. Tu Raspberry Pi > `...` > **Edit route settings**
3. Activa tanto **Use as exit node** como la ruta `192.168.1.0/24`

Ahora en tu Smart TV (Samsung/LG):
1. Ve a **Configuración de red** del TV
2. Cambia la **puerta de enlace (gateway)** manualmente a la IP de tu Raspberry Pi
3. El TV usará la Raspberry Pi como salida de red sin necesitar instalar nada.

---

### Solución de problemas frecuentes

| Problema | Solución |
|---|---|
| `raspberrypi.local` no responde | Busca la IP en tu router o usa la app **Fing** en el móvil |
| El exit node no aparece en la lista | Asegúrate de haberlo aprobado en **https://login.tailscale.com/admin/machines** |
| La IP sigue siendo la del país remoto | Desconecta y vuelve a conectar el exit node en la app Tailscale |
| Fire TV no encuentra Tailscale en la tienda | Activa "Fuentes desconocidas" y descarga el APK desde tailscale.com |
| Smart TV Samsung/LG no puede instalar apps | Usa la opción de gateway manual explicada en la sección anterior |
| PicoClaw no arranca | Ejecuta `sudo journalctl -u picoclaw.service -n 50` para ver el error |

---

## Resiliencia: IP dinámica y cortes de luz

- **IP dinámica:** Tailscale usa una red mesh basada en WireGuard. Si tu operador cambia tu IP pública, Tailscale renegocia la conexión automáticamente. No necesitas configurar puertos ni DDNS.
- **Cortes de luz:** Al volver la corriente, la Raspberry Pi arranca sola. Los servicios `tailscaled` y `picoclaw` están configurados en systemd para iniciarse automáticamente. El sistema queda operativo sin intervención manual.
