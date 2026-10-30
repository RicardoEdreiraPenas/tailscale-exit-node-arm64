# Seguridad

## Qué protege este proyecto y de qué

La placa está dentro de tu red de casa y reenvía el tráfico de tus dispositivos. Si alguien la
controla, puede ver ese tráfico (sin cifrar dentro de la placa) y atacar el resto de aparatos de
tu red. Las decisiones de diseño van dirigidas a que eso no pase.

| Riesgo | Cómo se mitiga |
|---|---|
| Descargas manipuladas | Todo lo que se descarga se comprueba contra una suma SHA-256 fijada en `versiones.conf`. La clave del repositorio de Tailscale se comprueba por su huella completa. Si no coincide, no se instala nada. |
| Acceso desde internet | Cortafuegos con la entrada cerrada. Solo entra SSH desde tu red local, el tráfico de Tailscale y el puerto de conexiones directas de Tailscale. No se abre ningún puerto en el router. |
| Contraseñas de SSH adivinadas | `scripts/endurecer_ssh.sh` deja solo el acceso con clave, sin root y con 3 intentos. |
| Paneles web expuestos | Los paneles de AdGuard y Pi-hole solo son accesibles por Tailscale y siempre con contraseña. Ya no queda un asistente de configuración abierto a la red local. |
| Un servicio comprometido toma el control | Cada servicio corre con su propio usuario sin privilegios y aislado por systemd (`ProtectSystem=strict`, sin capacidades salvo las imprescindibles, sin poder ganar privilegios). |
| El asistente de IA como puerta trasera | PicoClaw no ejecuta comandos, solo responde a tu ID de Telegram, no navega ni instala habilidades. Ver más abajo. |
| Secretos en el repositorio o a la vista | Tokens y claves en ficheros con permisos 600 fuera del repositorio. El token de Telegram no aparece en la línea de comandos (`ps`). |
| Software sin parchear | Actualizaciones de seguridad automáticas diarias del sistema y de Tailscale (`unattended-upgrades`). |

## PicoClaw

[PicoClaw](https://github.com/sipeed/picoclaw) es opcional. Todas sus versiones tienen una
vulnerabilidad publicada de inyección de comandos en su herramienta de shell
([CVE-2026-36045](https://github.com/advisories/GHSA-cv2p-68f4-f4pw)) sin parche conocido, y sus
autores no lo recomiendan en producción antes de la versión 1.0. Además, si la lista de usuarios
permitidos de un canal está vacía, PicoClaw acepta mensajes de cualquiera.

En versiones anteriores de este proyecto, el servicio corría con el usuario principal, que en
Raspberry Pi OS suele tener `sudo` sin contraseña, y la guía no pedía rellenar esa lista. El
instalador actual detecta esa configuración, para el servicio y obliga a reconfigurarlo.

## Lo que queda fuera

- La seguridad de tu cuenta de Tailscale: activa la verificación en dos pasos en tu proveedor
  de inicio de sesión. Quien entre en tu cuenta puede usar el exit node.
- El acceso físico a la placa: la microSD no va cifrada.
- El instalador de Pi-hole descarga después su propio motor (lo verifica con SHA-1) y clona sus
  repositorios; esa parte depende de la cadena de Pi-hole.

## Comunicar un problema

Abre una incidencia en el repositorio sin incluir datos sensibles, o escríbeme a
data@ricardoedreira.com si prefieres no hacerlo público.
