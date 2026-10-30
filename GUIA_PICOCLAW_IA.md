# Asistente de estado por Telegram con PicoClaw (opcional)

PicoClaw es un agente de IA que corre en la placa y responde por Telegram. En este proyecto se
usa para preguntar desde el móvil cómo está el exit node: si Tailscale está conectado, la
temperatura, la memoria o si el bloqueador funciona.

## Antes de nada: por qué el asistente no ejecuta comandos

PicoClaw puede ejecutar comandos en la máquina cuando la IA lo decide. Esa herramienta tiene
una vulnerabilidad de inyección de comandos publicada y sin parche (CVE-2026-36045), y los
propios desarrolladores avisan de que no es para producción antes de la versión 1.0. En un
equipo que está dentro de tu red de casa, eso es demasiado riesgo.

Por eso aquí el asistente:

- **No puede ejecutar comandos.** Lee un informe (`estado.txt`) que la placa regenera cada minuto.
- **Solo responde a tu ID de Telegram.** Si la lista de usuarios permitidos está vacía,
  PicoClaw acepta mensajes de cualquiera; el script se niega a arrancarlo así.
- **Corre con su propio usuario sin privilegios** y aislado por systemd: solo puede escribir en
  su carpeta, no ve tu carpeta personal ni puede ganar privilegios.
- **No navega por internet ni instala habilidades**, para que nadie pueda colarle instrucciones
  a través de una web.

## Requisitos

- Bot de Telegram: habla con **@BotFather**, escribe `/newbot` y guarda el token.
- Tu ID numérico de Telegram: escribe a **@userinfobot**.
- Una API key de un proveedor de IA. Google AI Studio (https://aistudio.google.com) tiene un
  nivel gratuito con Gemini.

## Instalación

```bash
sudo bash scripts/picoclaw.sh instalar
```

Descarga PicoClaw verificando su suma SHA-256, crea el usuario `picoclaw` y deja el servicio
preparado, pero sin arrancar.

```bash
sudo -u picoclaw -H picoclaw onboard
```

En el asistente:

- Canal: **Telegram**, con el token del bot.
- Usuarios permitidos (`allow_from`): **tu ID numérico**. No pongas tu nombre de usuario: se
  puede cambiar y suplantar.
- Proveedor: el de tu API key (por ejemplo Gemini, modelo `gemini-2.5-flash`).

PicoClaw guarda los secretos aparte, en `/var/lib/picoclaw/.picoclaw/.security.yml`.

```bash
sudo bash scripts/picoclaw.sh endurecer
```

Comprueba la configuración, desactiva lo peligroso, ajusta los permisos y arranca el servicio.
Si falta algo (por ejemplo, la lista de usuarios), lo explica y no arranca.

## Uso

Escribe al bot, por ejemplo:

- ¿Cómo está el sistema?
- ¿Está conectado Tailscale?
- ¿Qué temperatura tiene la placa?
- ¿Funciona el bloqueador de anuncios?

Si le pides que haga algo (reiniciar, actualizar), te dirá qué comando ejecutar por SSH.

## Si de verdad quieres que ejecute comandos

```bash
sudo bash scripts/picoclaw.sh endurecer --permitir-comandos
```

Activa la herramienta de comandos con los filtros de PicoClaw, pero el asistente sigue sin
`sudo`, aislado en su carpeta. Hazlo solo sabiendo que la vulnerabilidad sigue abierta.

## Cambiar de modelo

Vuelve a ejecutar el asistente y después `endurecer`:

```bash
sudo -u picoclaw -H picoclaw onboard
sudo bash scripts/picoclaw.sh endurecer
```

## Problemas frecuentes

| Problema | Solución |
|---|---|
| `endurecer` dice que falta `allow_from` | Repite `onboard` y pon tu ID numérico de Telegram |
| El bot no responde | `sudo systemctl status picoclaw` y `sudo journalctl -u picoclaw -n 50` |
| `401 Invalid API Key` | Clave mal copiada: repite `onboard` |
| `404 model no longer available` | El modelo se ha retirado: elige otro en `onboard` |
| El asistente dice que el informe es antiguo | `sudo systemctl status picoclaw-estado.timer` |

## Desinstalar

```bash
sudo bash scripts/picoclaw.sh desinstalar
```
