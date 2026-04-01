# Guía de Configuración: PicoClaw + IA (Asistente vía Telegram)

Guía para configurar PicoClaw como asistente de monitorización con IA accesible desde Telegram.

---

## ¿Qué es PicoClaw?

PicoClaw es una plataforma de agente IA que corre en la Raspberry Pi como servicio systemd. Permite interactuar con la IA desde Telegram para consultar el estado del sistema, ejecutar comandos y monitorizar el túnel Tailscale.

---

## Requisitos

- PicoClaw v0.2.4 instalado (lo hace automáticamente `scripts/install.sh`)
- Un bot de Telegram creado con **@BotFather**
- Una API key de Google AI Studio (gratuita)

---

## Parte 1 — Crear el bot de Telegram

1. Abre Telegram y busca **@BotFather**
2. Escribe `/newbot` y sigue las instrucciones
3. Guarda el **TOKEN** que te devuelve (formato: `1234567890:ABCdef...`)
4. Busca **@userinfobot** en Telegram y escríbele — te dará tu **CHAT_ID** numérico

---

## Parte 2 — Obtener API key de Google AI Studio

1. Ve a **https://aistudio.google.com**
2. Haz clic en **Get API Key** → **Create API key**
3. Copia la clave (empieza por `AIza...`)

> Es gratuita y no requiere tarjeta de crédito.

---

## Parte 3 — Configurar PicoClaw (primera vez)

Conéctate a la Raspberry Pi por SSH y ejecuta:

```bash
picoclaw onboard
```

Durante el asistente interactivo:
- Selecciona **Telegram** como canal
- Introduce el **TOKEN** del bot
- Introduce tu **CHAT_ID**
- Selecciona **Gemini** como proveedor de IA
- Introduce tu **API key de Google**

---

## Parte 4 — Actualizar el modelo de IA

PicoClaw viene configurado con modelos que pueden quedar obsoletos. El modelo gratuito recomendado actualmente es **Gemini 2.5 Flash**.

### Verificar qué modelo está configurado

```bash
jq '.agents.defaults.model_name' ~/.picoclaw/config.json
jq '.model_list[] | select(.model_name == "gemini-2.0-flash") | .model' ~/.picoclaw/config.json
```

### Actualizar al modelo actual (gemini-2.5-flash)

```bash
jq '(.model_list[] | select(.model_name == "gemini-2.0-flash")) |= . + {"model": "gemini/gemini-2.5-flash"}' ~/.picoclaw/config.json > /tmp/cfg.json && mv /tmp/cfg.json ~/.picoclaw/config.json

jq '.agents.defaults.model_name = "gemini-2.0-flash"' ~/.picoclaw/config.json > /tmp/cfg.json && mv /tmp/cfg.json ~/.picoclaw/config.json
```

### Añadir la API key de Gemini

```bash
jq '(.model_list[] | select(.model_name == "gemini-2.0-flash")) |= . + {"api_key": "TU_CLAVE_AQUI"}' ~/.picoclaw/config.json > /tmp/cfg.json && mv /tmp/cfg.json ~/.picoclaw/config.json
```

> **No compartas la API key en chats ni en el repositorio.**

### Reiniciar el servicio

```bash
sudo systemctl restart picoclaw.service
sudo systemctl status picoclaw.service
```

---

## Parte 5 — Probar el modelo antes de reiniciar

Antes de reiniciar el servicio, verifica que el modelo responde:

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$(jq -r '.model_list[] | select(.model_name == "gemini-2.0-flash") | .api_key' ~/.picoclaw/config.json)" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"di hola"}]}]}'
```

Si la respuesta incluye `"text": "¡Hola!"` (o similar), el modelo funciona correctamente.

---

## Parte 6 — Usar el asistente desde Telegram

Una vez configurado, abre Telegram y escribe al bot. Ejemplos de consultas:

- `¿Cuál es el estado del sistema?`
- `Comprueba si Tailscale está funcionando`
- `¿Cuánta RAM queda libre?`
- `¿Cuál es la temperatura de la CPU?`
- `¿Cuánto espacio libre hay en disco?`

El bot ejecutará los comandos necesarios en la Raspberry Pi y te responderá con los resultados.

---

## Solución de problemas

| Error | Causa | Solución |
|---|---|---|
| `401 Invalid API Key` | Clave mal copiada o duplicada | Verifica con `jq '.model_list[] | select(.model_name == "gemini-2.0-flash") | .api_key'` |
| `404 model no longer available` | Modelo retirado por Google | Actualiza a `gemini/gemini-2.5-flash` siguiendo la Parte 4 |
| `400 credit balance too low` | Sin crédito en Anthropic | Usa Gemini (gratuito) en lugar de Claude |
| `404 No endpoints found for free model` | Modelo gratuito de OpenRouter sin soporte de tools | Usa Gemini en lugar de OpenRouter |
| El bot no responde | Servicio caído | `sudo systemctl restart picoclaw.service` |
| Sigue usando modelo antiguo tras reinicio | El cambio no se guardó | Verifica con `jq '.agents.defaults.model_name'` antes de reiniciar |

---

## Modelos compatibles y gratuitos (Abril 2026)

| Modelo | Proveedor | Gratuito | Notas |
|---|---|---|---|
| `gemini-2.5-flash` | Google AI Studio | ✅ Sí | Recomendado |
| `gemini-2.5-pro` | Google AI Studio | ✅ Sí | Más potente, cuota menor |
| `gemini-2.0-flash` | Google AI Studio | ❌ Retirado | No disponible para nuevos usuarios |
| `claude-sonnet-4.6` | Anthropic | ❌ No | Requiere crédito de pago |
| Modelos OpenRouter free | OpenRouter | ⚠️ Parcial | No soportan herramientas (tools) |
