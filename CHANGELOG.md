# Cambios

## 2.0.0 (octubre de 2026): revisión de seguridad

### Seguridad
- PicoClaw pasa a ser opcional y deja de poder ejecutar comandos por defecto. Antes corría con el
  usuario principal (con `sudo`) y la guía no pedía limitar quién podía escribir al bot. Todas sus
  versiones tienen una inyección de comandos sin parche (CVE-2026-36045). Ahora corre con su propio
  usuario sin privilegios, aislado por systemd, exige tu ID de Telegram y se actualiza a v0.3.1.
- Todas las descargas se verifican con SHA-256 (`versiones.conf`). Antes se instalaban paquetes
  `.deb` como root sin comprobarlos, también desde una tarea cron nocturna.
- Tailscale se instala desde su repositorio apt firmado, comprobando la huella de la clave, en lugar
  de `curl | sh`.
- Cortafuegos (ufw): entrada cerrada salvo SSH desde la red local, Tailscale y su puerto de
  conexiones directas.
- AdGuard Home deja de correr como root y se instala ya configurado, con contraseña y el panel solo
  accesible por Tailscale. Antes el asistente inicial quedaba abierto a toda la red local.
- Nuevo `endurecer_ssh.sh`: SSH solo con clave, comprobando antes que la del usuario funciona.
- Actualizaciones de seguridad automáticas del sistema y de Tailscale con `unattended-upgrades`.
- El token de Telegram de las alertas sale del script a `/etc/exitnode/alertas.env` (permisos 600)
  y ya no aparece en la lista de procesos.
- La guía de Smart TV recomendaba anunciar toda la red local a Tailscale; se retira y se explica
  por qué no funcionaba.

### Rendimiento
- UDP GRO forwarding en la interfaz de salida, como recomienda Tailscale para exit nodes en Linux.
- El cortafuegos permite el puerto 41641/udp para que Tailscale use conexiones directas en vez de relés.
- AdGuard: sin límite de 20 consultas/s por /24 (todos los dispositivos de Tailscale comparten
  rango y se frenaban entre sí), caché de 8 MB con respuesta optimista.

### Nuevo
- Pi-hole como alternativa a AdGuard (`bloqueador.sh instalar pihole`), con comparación medida
  en `pruebas/laboratorio_dns/`.
- `pruebas/benchmark_pi.sh` y `pruebas/velocidad_cliente.sh` para medir en la placa real.
- Pruebas automáticas (bats, unittest, shellcheck) en GitHub Actions.
- El instalador detecta y desactiva la configuración insegura de versiones anteriores.

### Correcciones
- `status.sh` nunca detectaba el exit node aprobado: buscaba `"ExitNodeOption":true` sin espacio y
  Tailscale escribe el JSON con espacios. Ahora se lee con `jq`.
- `auto_update.sh` no actualizaba nunca (la URL tenía la versión fija). Se elimina; lo sustituyen
  `unattended-upgrades` y `update.sh`.
- `status.sh` mostraba campos equivocados de vnStat para el tráfico del mes.
- `uninstall.sh` forzaba el reenvío a 0 aunque otra cosa lo necesitara; ahora recarga la
  configuración del sistema.
- Las alertas avisan del corte de internet cuando vuelve la conexión (antes se perdían).
