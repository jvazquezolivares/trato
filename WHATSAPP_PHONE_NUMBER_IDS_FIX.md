# Fix WhatsApp Phone Number IDs Issue

## El Problema

La aplicación tiene **tres phone_number_ids** para manejar mensajes a providers y clientes por separado:

1. **`WHATSAPP_PROVIDER_PHONE_NUMBER_ID=1152919394565310`** → Para mensajes a PROVIDERS (técnicos, Miguel)
2. **`WHATSAPP_CLIENT_PHONE_NUMBER_ID=1196380060222507`** → Para mensajes a CLIENTES (Mariana)
3. **`WHATSAPP_PHONE_NUMBER_ID=1152919394565310`** → Legacy/default (igual al de providers)

**Error en Railway:**
```bash
# Estaba mal configurado así:
WHATSAPP_PHONE_NUMBER_ID="\"1152919394565310@"
# ❌ Tiene comillas escapadas y un @ al final
```

**Error en la aplicación:**
- `WhatsAppService.send_message` siempre usaba `WHATSAPP_PHONE_NUMBER_ID` sin permitir override
- Cuando un cliente escribía al número de clientes, el webhook llegaba correctamente
- Pero al responder, usaba el phone_number_id de providers
- **Meta rechazaba con HTTP 400: `(#100) Invalid parameter`**

## La Solución

### 1. Corregir Variables de Entorno en Railway

```bash
# Corregir esta variable:
WHATSAPP_PHONE_NUMBER_ID="1152919394565310"

# Verificar que también existan estas:
WHATSAPP_PROVIDER_PHONE_NUMBER_ID="1152919394565310"
WHATSAPP_CLIENT_PHONE_NUMBER_ID="1196380060222507"
```

### 2. Cambios en el Código (YA REALIZADOS)

#### `WhatsAppService` - Todos los métodos ahora aceptan `phone_number_id` opcional:

```ruby
# app/services/whatsapp_service.rb

# Antes:
WhatsAppService.send_message(to: phone, message: "Hola")

# Ahora (con override):
WhatsAppService.send_message(
  to: phone,
  message: "Hola",
  phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
)

# También aplica para:
# - send_multipart
# - send_list_message
# - send_message_with_buttons
# - send_template_message (ya lo tenía)
```

#### `ProviderConversationHandler` - Ahora usa el phone_number_id de providers:

```ruby
# app/services/provider_conversation_handler.rb

def self.send_welcome_and_store_state(phone)
  WhatsAppService.send_message(
    to: phone,
    message: WELCOME_MESSAGE,
    phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
  )
  # ...
end
```

#### `ClientAssistantOrchestrator` - Añadidos métodos helper:

```ruby
# app/services/client_assistant_orchestrator.rb

# Métodos helper privados para enviar mensajes:
def send_client_message(to:, message:)
  WhatsAppService.send_message(
    to: to,
    message: message,
    phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
  )
end

def send_provider_message(to:, message:)
  WhatsAppService.send_message(
    to: to,
    message: message,
    phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
  )
end

# Similar para send_client_list_message, send_client_message_with_buttons, send_client_multipart
```

### 3. Qué Falta Por Hacer

**PENDIENTE**: Reemplazar todas las llamadas directas a `WhatsAppService.*` en `ClientAssistantOrchestrator` con los métodos helper.

Este archivo tiene **50+ llamadas** a WhatsAppService que necesitan usar los métodos helper. Por ejemplo:

```ruby
# ❌ ANTES (usa phone_number_id incorrecto):
WhatsAppService.send_message(to: @from, message: "Hola")

# ✅ DESPUÉS (usa el phone_number_id de clientes):
send_client_message(to: @from, message: "Hola")
```

Similar para:
- `WhatsAppService.send_list_message` → `send_client_list_message`
- `WhatsAppService.send_message_with_buttons` → `send_client_message_with_buttons`
- `WhatsAppService.send_multipart` → `send_client_multipart`
- `WhatsAppService.send_message(to: @provider.phone, ...)` → `send_provider_message(to: @provider.phone, ...)`

### 4. Otros Servicios que Envían Mensajes

Estos servicios también deben especificar el `phone_number_id` correcto:

#### **Mensajes a PROVIDERS** (usan `WHATSAPP_PROVIDER_PHONE_NUMBER_ID`):
- `OnboardingService` → Ya usa el default correcto
- `ProviderAssistant` → Ya usa el default correcto
- `MorningSummaryJob` → Ya usa `send_template_message` con provider phone_number_id
- `PaymentReminderJob` → Ya usa `send_template_message` con provider phone_number_id
- `NewAppointmentRequestJob` → Ya usa `send_template_message` con provider phone_number_id

#### **Mensajes a CLIENTES** (usan `WHATSAPP_CLIENT_PHONE_NUMBER_ID`):
- `ReviewRequestJob` → Ya usa `send_template_message` con client phone_number_id
- `AppointmentReminderJob` → Ya usa `send_template_message` con phone_number_id específico según destinatario
- `Assistants::ReviewSummaryService` → ⚠️ NECESITA actualización
- `Assistants::EscalationDetector` → ⚠️ NECESITA actualización  
- `Assistants::AppointmentService` → ⚠️ NECESITA actualización
- `Assistants::SocialMediaService` → ⚠️ Envía a providers, usa default correcto
- `OtpService` → ⚠️ NECESITA análisis (puede enviar a ambos)
- `AdminService` → ⚠️ Envía a admins, usa default correcto

### 5. Pasos para Deployment

1. **Corregir variables en Railway**:
   ```bash
   railway variables set WHATSAPP_PHONE_NUMBER_ID="1152919394565310"
   ```

2. **Commit y push de los cambios**:
   ```bash
   git add .
   git commit -m "Fix: Add phone_number_id parameter to WhatsAppService methods for dual number support"
   git push origin main
   ```

3. **Verificar deployment en Railway**

4. **Probar con un mensaje real**:
   - Enviar mensaje desde tu número al número de clientes
   - Verificar en logs de Railway que la respuesta usa el phone_number_id correcto
   - Confirmar que el mensaje se envía exitosamente

### 6. Verificación en Logs

Buscar estos mensajes en Railway logs:

```
[WhatsAppService] Sending message to 522213515958 via phone_id: 1152919394565310
[WhatsAppService] Successfully sent message to 522213515958
```

O si falla:

```
[WhatsAppService] Failed to send message to 522213515958 (phone_id: 1152919394565310): HTTP 400 — {"error":...}
```

## Resumen

**COMPLETED:**
- ✅ `WhatsAppService` acepta `phone_number_id` opcional en todos los métodos
- ✅ `ProviderConversationHandler` usa `WHATSAPP_PROVIDER_PHONE_NUMBER_ID`
- ✅ `ClientAssistantOrchestrator` tiene métodos helper definidos
- ✅ Jobs con templates usan el phone_number_id correcto

**PENDING:**
- ⏳ Reemplazar todas las llamadas en `ClientAssistantOrchestrator` (50+ líneas)
- ⏳ Actualizar `Assistants::ReviewSummaryService`
- ⏳ Actualizar `Assistants::EscalationDetector`
- ⏳ Actualizar `Assistants::AppointmentService`
- ⏳ Corregir `WHATSAPP_PHONE_NUMBER_ID` en Railway
- ⏳ Hacer commit y deploy

**PRIORITY:**
1. Corregir Railway variables (URGENTE)
2. Terminar reemplazos en `ClientAssistantOrchestrator`
3. Actualizar servicios bajo `Assistants::`
