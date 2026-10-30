# Guía de instalación: exit node de Tailscale en Raspberry Pi

Guía paso a paso para convertir una Raspberry Pi (o Radxa ROCK 3C) en un nodo de
salida doméstico: navegas desde cualquier sitio con la IP de tu casa, cifrado de
extremo a extremo y sin abrir puertos en el router.

---

## Requisitos

- Raspberry Pi 4, 5 o Radxa ROCK 3C (64 bits)
- Tarjeta microSD de 8 GB o más
- Ordenador con Windows, macOS o Linux para preparar la microSD
- Mejor por cable que por Wi-Fi: el exit node reenvía todo el tráfico y el cable es más estable y rápido

---

## Parte 1. Preparar la microSD

1. Descarga **Raspberry Pi Imager** desde https://www.raspberrypi.com/software/
2. **Dispositivo:** tu modelo. **Sistema:** `Raspberry Pi OS (Other)` → **Raspberry Pi OS Lite (64-bit)**.
3. **Almacenamiento:** tu microSD.
4. En **Editar ajustes**:
   - **Usuario:** elige un nombre (no uses `pi`) y una contraseña larga.
   - **SSH:** actívalo y elige **"Permitir solo autenticación de clave pública"**. Pega tu clave pública
     (en Mac/Linux: `cat ~/.ssh/id_ed25519.pub`; si no tienes, créala con `ssh-keygen -t ed25519`).
     Si prefieres empezar con contraseña, más adelante `scripts/endurecer_ssh.sh` lo cambia por ti.
   - **Wi-Fi** (si no usas cable) y **zona horaria**.
5. **Escribir** y esperar.

---

## Parte 2. Primer arranque

```bash
ssh TU_USUARIO@raspberrypi.local          # o la IP que te dé el router
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git
git clone https://github.com/RicardoEdreiraPenas/tailscale-exit-node-arm64.git
cd tailscale-exit-node-arm64
```

---

## Parte 3. Instalación

```bash
sudo bash scripts/install.sh --bloqueador=adguard
```

Opciones: `--bloqueador=pihole` o `--bloqueador=ninguno`, `--con-picoclaw` (asistente de Telegram),
`--simular` (muestra lo que haría sin cambiar nada).

El instalador:

- Activa el reenvío de paquetes IPv4 e IPv6.
- Instala Tailscale desde su repositorio oficial, comprobando la huella de la clave de firma.
- Activa UDP GRO forwarding en la interfaz de salida, que es lo que recomienda Tailscale
  para que un exit node en Linux use menos CPU y vaya más rápido.
- Activa las actualizaciones de seguridad automáticas, incluidas las de Tailscale.
- Configura el cortafuegos: cierra todo lo que entra, salvo SSH desde tu red local, el tráfico
  de Tailscale y el puerto de conexiones directas de Tailscale (41641/udp).
- Si lo pides, instala el bloqueador de anuncios con la descarga verificada.
- Detecta restos de versiones anteriores del proyecto y los desactiva.

### Activar el exit node

```bash
sudo tailscale up --advertise-exit-node
```

Abre el enlace que aparece para añadir la placa a tu cuenta. Después, en
https://login.tailscale.com/admin/machines, abre la placa → **Edit route settings** →
marca **Use as exit node**.

> Si ya habías usado `tailscale up` con otras opciones, Tailscale te pedirá repetirlas.
> Copia el comando exacto que te sugiere el error.

### Comprobar

```bash
sudo bash scripts/status.sh
```

Todo debe salir en verde. Si algo falla, el propio panel indica el comando para arreglarlo.

---

## Parte 4. Seguridad recomendada (5 minutos)

1. **SSH solo con clave** (si no lo elegiste en el paso 1):
   ```bash
   sudo bash scripts/endurecer_ssh.sh
   ```
   Comprueba que tu clave funciona antes de tocar nada, para que no te quedes fuera.

2. **Caducidad de la clave de la máquina.** Por defecto, Tailscale pide volver a iniciar sesión
   en cada máquina cada 180 días. Es más seguro dejarlo así: te llegará un correo antes. Si
   prefieres que el exit node no caduque nunca, en el panel de la máquina elige
   **Disable key expiry**, sabiendo que si alguien roba la tarjeta tendrá acceso hasta que la
   borres del panel.

3. **Quién puede usar el exit node.** Si compartes tu red de Tailscale con otras personas, limita
   en las ACL (https://login.tailscale.com/admin/acls) quién puede usar `autogroup:internet`.

---

## Parte 5. Bloqueador de anuncios

```bash
sudo bash scripts/bloqueador.sh instalar adguard     # o: pihole
```

Solo puede haber uno: los dos usan el puerto 53. Al terminar, el script muestra la dirección del
panel (solo accesible por Tailscale, puerto 8080) y la contraseña. Guárdala en tu gestor de
contraseñas.

Para que tus dispositivos lo usen: en https://login.tailscale.com/admin/dns →
**Add nameserver** → **Custom** → la IP de Tailscale de la placa, y activa **Override DNS servers**.

> Si la placa se apaga, los dispositivos conectados a Tailscale se quedan sin DNS hasta que
> vuelva o la quites de ahí.

¿Cuál elegir? En `pruebas/laboratorio_dns/RESULTADOS.md` está la comparación medida: en velocidad
empatan y ninguno frena la conexión. AdGuard cifra las consultas hacia fuera; por eso es el
recomendado.

---

## Parte 6. Alertas por Telegram (opcional)

```bash
sudo bash scripts/alertas.sh --configurar
```

Te pide el token del bot (de @BotFather) y tu ID numérico (de @userinfobot), envía un mensaje de
prueba y activa una comprobación cada 5 minutos. Avisa si se cae Tailscale o el bloqueador, si se
llena el disco, si sube la temperatura o si hubo un corte de internet. El token queda en
`/etc/exitnode/alertas.env`, legible solo por root.

---

## Parte 7. Asistente PicoClaw (opcional)

Ver [GUIA_PICOCLAW_IA.md](GUIA_PICOCLAW_IA.md). Por seguridad, el asistente solo lee un informe de
estado y no puede ejecutar comandos.

---

## Parte 8. Mantenimiento

```bash
git pull && sudo bash scripts/update.sh   # actualiza todo a las versiones fijadas del repositorio
sudo bash scripts/status.sh               # panel de estado
sudo journalctl -u tailscaled -f          # registro de Tailscale
sudo bash scripts/uninstall.sh            # deshace la instalación (pregunta antes de quitar Tailscale)
```

El sistema y Tailscale ya se actualizan solos cada día. `update.sh` sirve para aplicar al momento
las versiones nuevas del bloqueador o de PicoClaw que se fijen en `versiones.conf`.

---

## Parte 9. Prueba desde el móvil

1. Quita el Wi-Fi del móvil y quédate con datos móviles.
2. En la app de Tailscale, activa la VPN → **Use exit node** → tu placa.
3. Busca "cuál es mi IP". Debe salir el operador de tu casa, no el del móvil.

Para medir la velocidad con y sin exit node desde un Mac o Linux:

```bash
bash pruebas/velocidad_cliente.sh NOMBRE_DE_LA_PLACA
```

Y en la placa, la latencia DNS, el bloqueo y la calidad de la conexión de Tailscale:

```bash
sudo bash pruebas/benchmark_pi.sh
```

---

## Parte 10. Conectar tus dispositivos

| Dispositivo | Cómo |
|---|---|
| Windows | Instala Tailscale (https://tailscale.com/download/windows) → icono de la barra → **Exit Node** → tu placa |
| Mac | Tailscale desde la App Store → barra de menú → **Exit Node** → tu placa |
| iPhone / Android | App de Tailscale → **Use exit node** → tu placa |
| Android TV / Google TV | Tailscale desde Google Play → activa **Exit Node** |
| Fire TV Stick | Ver abajo |
| Smart TV Samsung o LG | Ver abajo |

### Fire TV Stick

Tailscale no está en la tienda de Amazon; se instala su APK oficial.

1. Configuración → Mi Fire TV → Acerca de → pulsa 7 veces el nombre del dispositivo
   (activa las opciones de desarrollador) → permite **apps de origen desconocido**.
2. Instala **Downloader** desde la tienda del Fire TV.
3. En Downloader escribe `https://pkgs.tailscale.com/stable/` (con `https`), baja hasta
   **Universal Android application package (APK)** y descarga la versión más reciente.
4. Instala, borra el APK, abre Tailscale, escanea el QR con el móvil y elige tu placa como exit node.

### Smart TV Samsung o LG (sin Tailscale)

Estos televisores no pueden instalar Tailscale. La guía anterior proponía poner la Raspberry como
puerta de enlace del televisor, pero eso no sirve: si el televisor está en tu casa ya sale con tu
IP, y si está en otra casa no puede llegar a la Raspberry sin Tailscale. Además, anunciar toda tu
red local (`--advertise-routes=192.168.1.0/24`) expone todos los aparatos de casa a cualquier
dispositivo de tu cuenta de Tailscale.

Opciones que sí funcionan cuando el televisor está fuera de casa:

- **Un Chromecast con Google TV o un Fire TV Stick** conectado al televisor, con Tailscale. Es lo
  más barato y sencillo.
- **Un router de viaje con Tailscale** (por ejemplo GL.iNet) en la otra casa, configurado para
  usar tu placa como exit node. Todo lo que se conecte a ese router saldrá por tu casa.

---

## Solución de problemas

| Problema | Solución |
|---|---|
| `raspberrypi.local` no responde | Busca la IP en tu router o con la app Fing |
| El exit node no aparece | Apruébalo en https://login.tailscale.com/admin/machines → Edit route settings |
| Va lento y `status.sh` dice "por relé" | La conexión usa un servidor intermedio. Comprueba que tu router no bloquea UDP saliente; el cortafuegos de la placa ya permite 41641/udp |
| `status.sh` avisa de UDP GRO | Tu kernel es anterior al 6.2. Funciona igual; con `sudo apt full-upgrade` y reinicio suele resolverse |
| Los dispositivos se quedan sin internet | Probablemente la placa está apagada y es el DNS de Tailscale. Quítala de "Nameservers" o enciéndela |
| `changing settings via 'tailscale up' requires mentioning all non-default flags` | Copia el comando completo que sugiere el error |
| Error `Bad message` o `cannot append to alternatives.log` | La microSD tiene errores de escritura. Ver abajo |

**Reparar errores de escritura en la microSD:**

```bash
sudo touch /forcefsck && sudo reboot
# tras reiniciar:
sudo dpkg --configure -a
sudo apt --fix-broken install -y
sudo bash scripts/install.sh
```

Si el error vuelve, la tarjeta está fallando: graba una nueva.

---

## Resiliencia

- **IP dinámica:** Tailscale renegocia la conexión sola cuando tu operador cambia tu IP. No hace
  falta abrir puertos ni configurar DDNS.
- **Cortes de luz:** al volver la corriente, la placa arranca y systemd levanta todos los servicios.
  Si tienes las alertas activas, te llega un aviso del corte de internet cuando vuelve la conexión.
