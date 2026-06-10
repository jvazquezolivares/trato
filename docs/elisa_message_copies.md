# Elisa Message Copies Documentation

## Overview

This document explains how Elisa's conversational message copies are organized and managed in the Trato application. All user-facing messages that Elisa sends via WhatsApp are centralized in YAML i18n files for easy management, consistency, and future internationalization support.

**File Location:** `config/locales/elisa_es.yml`

**Source of Truth:** All message copies must match the specifications defined in `KIRO_PROMPT_FLOWS_v5.md`

## Table of Contents

1. [YAML Structure](#yaml-structure)
2. [Naming Conventions](#naming-conventions)
3. [Interpolation Variables](#interpolation-variables)
4. [Adding New Messages](#adding-new-messages)
5. [Future Internationalization](#future-internationalization)
6. [Usage Examples](#usage-examples)
7. [Best Practices](#best-practices)

---

## YAML Structure

The YAML file follows Rails i18n conventions with a clear hierarchical structure:

```yaml
es:
  elisa:
    provider:          # Provider-facing messages (P1-P20 flows)
      onboarding:      # Flow category
        welcome: "..."
        greeting: "Mucho gusto, %{name} 👋"
      bio:
        approval_prompt: "..."
      list_messages:
        decline_reasons:
          title: "..."
          options: [...]
    
    client:            # Client-facing messages (C1-C7 flows)
      region_detection:
        greeting: "..."
      appointment:
        notification_header: "..."
      emergency:
        client_alert: "..."
```

### Top-Level Organization

- **`es`** — Locale identifier (Spanish)
- **`elisa`** — Namespace for all Elisa message copies
- **`provider`** — Messages sent to providers (P1-P20 flows)
- **`client`** — Messages sent to clients (C1-C7 flows)

### Flow Categories

Messages are grouped by conversational flow or feature area:

**Provider Categories:**
- `onboarding` — Initial registration and field collection (P1-P8)
- `bio` — Biography generation and approval (P9-P10)
- `photos` — Photo collection (P11-P12)
- `facebook` — Facebook page integration (P13)
- `email` — Email collection (P14)
- `completion` — Profile activation (P16)
- `capabilities` — Feature explanation (P18)
- `auto_reply` — Auto-reply setup (P18H)
- `morning_summary` — Daily task reminders (P19)
- `list_messages` — List Message structures

**Client Categories:**
- `region_detection` — Geographic confirmation (C2A)
- `appointment` — Appointment scheduling (C1A)
- `emergency` — Emergency escalation (C5A)
- `review` — Review collection (C7A)
- `list_messages` — List Message structures

---

## Naming Conventions

### Key Naming Rules

1. **Use dot-notation:** `elisa.[provider|client].[category].[message_name]`
2. **Key names in English:** Even though message content is in Spanish, key names must be in English for locale-agnostic structure
3. **Descriptive names:** Use clear, semantic names that describe the message's purpose
4. **Snake_case:** Use lowercase with underscores (e.g., `notification_header`, `client_alert`)

### Examples

✅ **Good Key Names:**
```yaml
onboarding:
  welcome: "..."
  greeting: "..."
  decline_closing: "..."
  
emergency:
  client_alert: "..."
  provider_alert: "..."
```

❌ **Bad Key Names:**
```yaml
onboarding:
  msg1: "..."           # Not descriptive
  bienvenida: "..."     # Spanish word, not locale-agnostic
  welcomeMessage: "..." # camelCase instead of snake_case
```

### List Message Structure

List Messages follow a nested structure with specific keys:

```yaml
list_messages:
  [message_name]:
    title: "..."       # List header (required)
    body: "..."        # Explanatory text (optional)
    button: "..."      # Button label (required, ≤20 characters)
    options:           # Array of selectable options
      - "Option 1"
      - "Option 2"
```

---

## Interpolation Variables

Many messages include dynamic content that changes based on context (names, dates, phone numbers, etc.). Rails i18n uses the `%{variable_name}` syntax for interpolation.

### Common Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `name` | String | Person's first name | "Miguel" |
| `state` | String | Geographic region/state | "Veracruz" |
| `city` | String | City name | "Ciudad de México" |
| `phone` | String | Formatted phone number | "+52 229 123 4567" |
| `date` | String | Formatted date | "15 de marzo" |
| `time` | String | Time | "10:00 AM" |
| `rating` | Integer | Star rating (1-5) | 5 |
| `count` | Integer | Numeric count | 3 |
| `profile_url` | String | Full URL to profile | "https://trato.com/miguel" |
| `assistant_link` | String | WhatsApp link | "https://wa.me/..." |
| `provider_name` | String | Provider's name | "Miguel" |
| `keyword` | String | Emergency keyword | "chispa" |

### Defining Messages with Interpolation

**In YAML:**
```yaml
greeting: "Mucho gusto, %{name} 👋 ¿A qué te dedicas?..."
area_prompt: "¿En qué zonas o colonias de %{city} das servicio?"
client_alert: "🚨 %{name}, esto suena urgente. Llama a %{provider_name} AHORA: 📞 %{phone}"
```

**In Ruby Code:**
```ruby
I18n.t('elisa.provider.onboarding.greeting', name: provider.name)
I18n.t('elisa.provider.onboarding.area_prompt', city: provider.city)
I18n.t('elisa.client.emergency.client_alert', 
  name: client.name, 
  provider_name: provider.name, 
  phone: provider.formatted_phone
)
```

### Documenting Required Variables

**Always add comments documenting required interpolation variables:**

```yaml
# P2B: Greeting after name is provided
# Variables: name (string) — provider's first name
# Example: "Mucho gusto, Miguel 👋 ¿A qué te dedicas?..."
greeting: "Mucho gusto, %{name} 👋 ¿A qué te dedicas?..."

# C5A: Alert sent to client when emergency detected
# Variables:
#   - name (string) — client's first name
#   - provider_name (string) — provider's first name
#   - phone (string) — provider's phone number (formatted)
# Example: "🚨 María, esto suena urgente. Aléjate del panel y llama a Miguel AHORA..."
client_alert: "🚨 %{name}, esto suena urgente. Llama a %{provider_name} AHORA: 📞 %{phone}"
```

### Grammar Notes for Spanish Interpolation

When writing messages with interpolation in Spanish, pay attention to:

1. **Gender agreement:** Spanish adjectives and articles must agree with nouns in gender
2. **Prepositions:** Use correct prepositions (`de`, `a`, `en`) before interpolated values
3. **Pronouns:** Use appropriate object pronouns (`le`, `te`, `lo/la`)

**Example:**
```yaml
# Correct: "le ayuda" (indirect object pronoun)
comment_request: "Tu comentario le ayuda mucho a %{name}..."

# Correct: "de" preposition before number
rating_ack: "¡Gracias por tu calificación de %{rating} ⭐!"
```

---

## Adding New Messages

Follow this process when adding new message copies to the YAML file:

### Step 1: Identify the Flow

Determine which flow and category the message belongs to:
- Is it provider-facing or client-facing?
- Which conversation flow (P1-P20 or C1-C7)?
- Which category does it fit under?

### Step 2: Choose a Key Name

Create a descriptive, English key name following the naming conventions:
- Use snake_case
- Be specific about the message's purpose
- Group related messages under common prefixes

### Step 3: Add to YAML File

Insert the message in the appropriate location with:
- **Flow ID comment:** Link to the flow specification (e.g., `# P5A: Service area prompt`)
- **Variable documentation:** List all required interpolation variables
- **Example:** Show how the message looks with sample data (optional but helpful)
- **Grammar notes:** Document any Spanish-specific considerations (optional)

### Step 4: Update Code

Replace hardcoded strings with `I18n.t()` calls:

```ruby
# Before
def send_message
  whatsapp.send_text(
    to: provider.phone,
    message: "¿En qué zonas trabajas?"
  )
end

# After
def send_message
  whatsapp.send_text(
    to: provider.phone,
    message: I18n.t('elisa.provider.onboarding.area_prompt', city: provider.city)
  )
end
```

### Step 5: Validate and Test

- Run `rails runner "I18n.backend.load_translations"` to validate YAML syntax
- Run relevant RSpec tests to ensure messages render correctly
- For List Messages, verify button labels are ≤20 characters
- Test that all interpolation variables are passed correctly

### Complete Example

**YAML:**
```yaml
provider:
  specialties:
    # P6A: Specialties prompt
    # Variables: none
    prompt: "¿Hay algo en lo que te especialices? Por ejemplo: urgencias, instalaciones nuevas..."
    
    # P6A: Specialties validation error
    # Variables: none
    required: "¿En qué te especializas?"
```

**Ruby Code:**
```ruby
# In OnboardingService
def ask_for_specialties
  whatsapp.send_text(
    to: provider.phone,
    message: I18n.t('elisa.provider.specialties.prompt')
  )
end

def validate_specialties(response)
  if response.blank?
    whatsapp.send_text(
      to: provider.phone,
      message: I18n.t('elisa.provider.specialties.required')
    )
  end
end
```

### Adding List Messages

List Messages require a specific structure:

**YAML:**
```yaml
list_messages:
  work_hours:
    title: "¿Cuándo trabajas?"
    body: "Ayúdame a organizar tu agenda"
    button: "Ver opciones"     # Must be ≤20 characters
    options:
      - "Lunes a viernes"
      - "Todos los días"
      - "Solo fines de semana"
      - "Horario variable"
```

**Ruby Code:**
```ruby
# In ListMessageBuilder
def build_work_hours_list
  {
    type: "list",
    header: { 
      type: "text", 
      text: I18n.t('elisa.provider.list_messages.work_hours.title')
    },
    body: { 
      text: I18n.t('elisa.provider.list_messages.work_hours.body')
    },
    action: {
      button: I18n.t('elisa.provider.list_messages.work_hours.button'),
      sections: [
        {
          rows: I18n.t('elisa.provider.list_messages.work_hours.options').map.with_index do |option, index|
            { id: "option_#{index}", title: option }
          end
        }
      ]
    }
  }
end
```

---

## Future Internationalization

The YAML structure is designed to support multiple languages in the future. Currently, all messages are in Spanish (`es` locale), but the system is prepared for English, Portuguese, or other languages.

### Adding a New Language

To add English translations, create a new file following the same structure:

**File:** `config/locales/elisa_en.yml`

```yaml
en:
  elisa:
    provider:
      onboarding:
        welcome: "Hello! 👋 I'm Elisa from Trato. I'll help you create your profile..."
        greeting: "Nice to meet you, %{name} 👋"
        # ... same keys as Spanish version
```

### Key Structure Remains the Same

The key names stay in English across all locales:

```yaml
# Spanish (elisa_es.yml)
es:
  elisa:
    provider:
      onboarding:
        welcome: "¡Hola! 👋 Soy Elisa..."

# English (elisa_en.yml)
en:
  elisa:
    provider:
      onboarding:
        welcome: "Hello! 👋 I'm Elisa..."

# Portuguese (elisa_pt.yml)
pt:
  elisa:
    provider:
      onboarding:
        welcome: "Olá! 👋 Sou Elisa..."
```

### Locale Selection in Code

Rails i18n automatically selects the appropriate locale:

```ruby
# Set locale globally
I18n.locale = :en

# Or pass locale explicitly
I18n.t('elisa.provider.onboarding.welcome', locale: :en)
```

### Interpolation Variables Are Locale-Agnostic

Variable names remain the same across all languages:

```yaml
# Spanish
greeting: "Mucho gusto, %{name} 👋"

# English
greeting: "Nice to meet you, %{name} 👋"

# Portuguese
greeting: "Prazer em conhecê-lo, %{name} 👋"
```

Code doesn't change:
```ruby
I18n.t('elisa.provider.onboarding.greeting', name: provider.name)
```

### Translation Workflow

When adding new languages:

1. **Copy structure:** Use `elisa_es.yml` as the template
2. **Translate content only:** Keep all key names in English
3. **Preserve formatting:** Maintain emojis, line breaks, and punctuation
4. **Respect grammar:** Adjust word order and grammar for the target language
5. **Test interpolation:** Verify that interpolated variables work grammatically in all contexts

### Locale Detection Strategy (Future)

Potential approaches for detecting client/provider language preference:

- **Phone number region:** Infer locale from country code (e.g., +1 = English, +52 = Spanish)
- **User preference:** Allow users to select language in profile settings
- **First interaction:** Ask for language preference at the start of onboarding
- **Browser detection:** Use Accept-Language header for web-based interactions

**Note:** This is not yet implemented. Currently, all messages default to Spanish (`es`).

---

## Usage Examples

### Simple Message (No Variables)

**YAML:**
```yaml
onboarding:
  name_prompt: "¡Qué bueno que quieres registrarte! 🎉 ¿Cómo te llamas?"
```

**Ruby:**
```ruby
message = I18n.t('elisa.provider.onboarding.name_prompt')
# => "¡Qué bueno que quieres registrarte! 🎉 ¿Cómo te llamas?"
```

### Message with Interpolation

**YAML:**
```yaml
greeting: "Mucho gusto, %{name} 👋 ¿A qué te dedicas?..."
```

**Ruby:**
```ruby
message = I18n.t('elisa.provider.onboarding.greeting', name: "Miguel")
# => "Mucho gusto, Miguel 👋 ¿A qué te dedicas?..."
```

### List Message Options

**YAML:**
```yaml
list_messages:
  experience:
    options:
      - "1–3 años"
      - "4–6 años"
      - "7–10 años"
      - "Más de 10 años"
```

**Ruby:**
```ruby
options = I18n.t('elisa.provider.list_messages.experience.options')
# => ["1–3 años", "4–6 años", "7–10 años", "Más de 10 años"]

# Map to List Message rows
rows = options.map.with_index do |option, index|
  { id: "exp_#{index}", title: option }
end
```

### Multiple Variables

**YAML:**
```yaml
completion:
  message: "¡Listo, %{name}! Tu perfil ya está activo 🎉\n\nTu página: %{profile_url}\nLink de tu asistente: %{assistant_link}"
```

**Ruby:**
```ruby
message = I18n.t(
  'elisa.provider.completion.message',
  name: provider.name,
  profile_url: provider.profile_url,
  assistant_link: provider.assistant_whatsapp_link
)
# => "¡Listo, Miguel! Tu perfil ya está activo 🎉\n\nTu página: https://trato.com/miguel\n..."
```

### Conditional Messages

**YAML:**
```yaml
morning_summary:
  with_tasks_header: "Tienes %{count} %{tasks_word} de ayer:"
  no_tasks: "¿Tienes pendientes para hoy?"
  singular_task: "pendiente"
  plural_tasks: "pendientes"
```

**Ruby:**
```ruby
if pending_tasks.any?
  tasks_word = I18n.t(
    pending_tasks.count == 1 ? 
      'elisa.provider.morning_summary.singular_task' : 
      'elisa.provider.morning_summary.plural_tasks'
  )
  
  message = I18n.t(
    'elisa.provider.morning_summary.with_tasks_header',
    count: pending_tasks.count,
    tasks_word: tasks_word
  )
else
  message = I18n.t('elisa.provider.morning_summary.no_tasks')
end
```

---

## Best Practices

### 1. Always Use Comments

Document every message with:
- Flow ID (P1A, C7A, etc.)
- Required interpolation variables
- Optional example with sample data

```yaml
# P2B: Greeting after name is provided
# Variables: name (string) — provider's first name
# Example: "Mucho gusto, Miguel 👋 ¿A qué te dedicas?..."
greeting: "Mucho gusto, %{name} 👋 ¿A qué te dedicas?..."
```

### 2. Keep Messages Close to Code

When refactoring code to use i18n:
- Extract the message to YAML first
- Update the code immediately after
- Run tests to ensure nothing breaks

### 3. Validate Button Labels

List Message buttons have a 20-character limit enforced by WhatsApp:

✅ **Good:** `"Ver opciones"` (12 characters)
✅ **Good:** `"Seleccionar"` (12 characters)
❌ **Bad:** `"Ver todas las opciones disponibles"` (34 characters)

### 4. Preserve Emojis and Formatting

- Emojis should render correctly in UTF-8
- Preserve `\n` for line breaks
- Bold markers (`*text*`) are part of WhatsApp formatting

```yaml
notification_header: "📋 *Nueva cita agendada*"
```

### 5. Match Specification Exactly

All message copies must match `KIRO_PROMPT_FLOWS_v5.md`:
- Exact wording
- Same emojis
- Same punctuation
- Same formatting

### 6. Don't Mix System Instructions with Messages

**Only user-facing WhatsApp messages belong in YAML.**

❌ **Do NOT include:**
- AI prompt builder instructions (`ProviderPromptBuilder`, `ClientPromptBuilder`)
- System prompts for Claude AI
- Internal service logic messages

✅ **DO include:**
- Messages sent to providers via WhatsApp
- Messages sent to clients via WhatsApp
- List Message structures

### 7. Test Interpolation Thoroughly

Always test that:
- All required variables are passed
- Variables display correctly in the message
- Spanish grammar is correct with interpolated values

```ruby
# RSpec example
describe "message interpolation" do
  it "passes provider name correctly" do
    provider = build(:provider, name: "Miguel")
    message = service.greeting(provider)
    
    expect(message).to include("Miguel")
    expect(message).to eq(
      I18n.t('elisa.provider.onboarding.greeting', name: "Miguel")
    )
  end
end
```

### 8. Use Descriptive Key Names

Choose key names that clearly indicate the message's purpose:

✅ **Good:**
- `decline_closing` — Message shown when provider declines registration
- `emergency_client_alert` — Alert sent to client in emergency
- `notification_header` — Header for appointment notification

❌ **Bad:**
- `message1` — Not descriptive
- `alert` — Too generic
- `text` — Meaningless

### 9. Group Related Messages

Keep related messages together under common prefixes:

```yaml
bio:
  approval_prompt: "..."
  retry_dictation: "..."
  resend: "..."
  regenerating: "..."

photos:
  profile_prompt: "..."
  profile_ack: "..."
  work_prompt: "..."
  work_ack: "..."
```

### 10. Validate YAML Syntax

Before committing changes, validate the YAML file:

```bash
rails runner "I18n.backend.load_translations"
```

If there are syntax errors, this command will fail with details.

---

## Summary

The YAML i18n structure provides a centralized, maintainable, and internationalization-ready approach to managing all of Elisa's conversational message copies. By following the naming conventions, documenting interpolation variables, and adhering to best practices, developers can easily add new messages and update existing ones without touching business logic.

**Key Takeaways:**

- All messages are in `config/locales/elisa_es.yml`
- Use descriptive English key names in snake_case
- Document all interpolation variables in comments
- Match message copies to `KIRO_PROMPT_FLOWS_v5.md` exactly
- The structure supports future internationalization (English, Portuguese, etc.)
- Always validate YAML syntax and test messages after changes

For questions or clarification, refer to the Design Document in `.kiro/specs/elisa-message-copy-verification/design.md`.
