# Seguridad

## Qué protege este proyecto y de qué

La placa está dentro de tu red de casa y reenvía el tráfico de tus dispositivos. Si alguien la
controla, puede ver ese tráfico (sin cifrar dentro de la placa) y atacar el resto de aparatos de
tu red. Las decisiones de diseño van dirigidas a que eso no pase.

| Riesgo | Cómo se mitiga |
|---|---|
| Descargas manipuladas | AdGuard, PicoClaw y el instalador de Pi-hole se comprueban contra una suma SHA-256 fijada en `versiones.conf`; la clave del repositorio de Tailscale, por su huella completa. Si no coincide, no se instala nada. Las listas de bloqueo no se verifican: las descarga el propio bloqueador. |
| Acceso desde internet | Cortafuegos con la entrada cerrada. Desde la red local solo se llega a SSH (y al DNS si hay bloqueador). Llega el puerto de conexiones directas de Tailscale, cifrado y autenticado. No se abre ningún puerto en el router. |
| Otros dispositivos de tu red de Tailscale | Todo lo que entra por la interfaz de Tailscale está permitido (SSH, DNS, paneles). Tailscale mete sus propias reglas por delante del cortafuegos, así que esto lo controlan las ACL de tu cuenta de Tailscale, no ufw. Si compartes tu red de Tailscale, limita ahí quién llega a la placa. |
| Contraseñas de SSH adivinadas | `scripts/endurecer_ssh.sh` deja solo el acceso con clave, sin root y con 3 intentos. |
| Paneles web expuestos | Los paneles de AdGuard y Pi-hole quedan siempre con contraseña y, con el cortafuegos activo, solo son accesibles por Tailscale. Ya no queda un asistente de configuración abierto a la red local. Con `--sin-firewall` los paneles quedan accesibles desde la red local. |
| Un servicio comprometido toma el control | AdGuard, PicoClaw y las alertas corren con su propio usuario sin privilegios y aislados por systemd (`ProtectSystem=strict`, sin capacidades salvo las imprescindibles, sin poder ganar privilegios). Lo que root hace en la carpeta de PicoClaw se hace como el usuario `picoclaw`, para que un enlace simbólico no pueda desviar una escritura de root. Tailscale y las tareas de mantenimiento corren como root. |
| El asistente de IA como puerta trasera | PicoClaw no ejecuta comandos, solo responde a tu ID de Telegram, no navega ni instala habilidades. Ver más abajo. |
| Secretos en el repositorio o a la vista | Tokens y claves en ficheros con permisos 600 fuera del repositorio. El token de Telegram no aparece en la línea de comandos (`ps`). |
| Software sin parchear | Actualizaciones de seguridad automáticas diarias del sistema y de Tailscale (`unattended-upgrades`). |

## PicoClaw

[PicoClaw](https://github.com/sipeed/picoclaw) es opcional. Todas sus versiones tienen una
vulnerabilidad publicada de inyección de comandos en su herramienta de shell
(CVE-2026-36045, [GO-2026-5867](https://pkg.go.dev/vuln/GO-2026-5867)) sin parche conocido, y sus
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
  repositorios, y `pihole -up` (en `update.sh`) instala siempre la última versión: esa parte
  depende de la cadena de Pi-hole.
- El asistente PicoClaw envía el informe de estado (nombre de la placa, IP de Tailscale, servicios)
  al proveedor de IA que elijas.

## Comunicar un problema

Abre una incidencia en el repositorio sin incluir datos sensibles, o escríbeme a
data@ricardoedreira.com si prefieres no hacerlo público.
