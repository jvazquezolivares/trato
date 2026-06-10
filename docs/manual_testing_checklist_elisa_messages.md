# Manual Testing Checklist — Elisa Message Copy Verification

## Overview

This checklist verifies that all Elisa conversational message copies extracted to `config/locales/elisa_es.yml` match KIRO_PROMPT_FLOWS_v5.md specifications and render correctly in the WhatsApp environment.

**Spec:** elisa-message-copy-verification  
**Task:** 4.4 Manual smoke testing of critical flows  
**Requirements:** 8.6  
**Environment:** WhatsApp Web or mobile app connected to Trato test numbers  
**Testing Date:** _____________________  
**Tester:** _____________________

---

## Prerequisites

Before starting manual testing:

- [ ] Both WhatsApp test numbers are configured and accessible
  - Provider number: `WHATSAPP_PROVIDER_PHONE_NUMBER_ID`
  - Client number: `WHATSAPP_CLIENT_PHONE_NUMBER_ID`
- [ ] Test providers and clients are created in staging/development database
- [ ] WhatsApp Web or WhatsApp mobile app is logged in and ready
- [ ] Copy of KIRO_PROMPT_FLOWS_v5.md is available for reference

---

## Test Plan Overview

This checklist focuses on critical flows with high user visibility and complex message structures:

1. **P1A**: Welcome message (first impression)
2. **P1B**: Decline reasons List Message (6 options)
3. **C2A**: Region detection greeting with interpolation
4. **C5A**: Emergency alerts to both client and provider
5. **C7A**: Rating List Message (5 star options)
6. **Cross-cutting**: Emoji rendering in WhatsApp

---

## Section 1: Provider Flow Testing

### Test 1.1: P1A Welcome Message

**Flow ID:** P1A  
**Message Key:** `elisa.provider.onboarding.welcome`  
**Expected Copy:**
```
¡Hola! 👋 Soy Elisa de Trato. Te voy a ayudar a crear tu perfil de técnico. ¿Listo para empezar?
```

**Test Steps:**
1. Send any message to the **provider WhatsApp number** from a new phone number (not previously registered)
2. Observe the welcome message that Elisa sends back

**Verification Checklist:**
- [ ] Message displays exactly as specified above
- [ ] Emoji 👋 renders correctly in WhatsApp
- [ ] Message tone is friendly and clear
- [ ] No typos or grammatical errors
- [ ] Message arrives within 2-3 seconds

**Actual Result:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail  

**Notes/Issues:** ___________________________________________

---

### Test 1.2: P1B Decline Reasons List Message

**Flow ID:** P1B  
**Message Keys:** `elisa.provider.list_messages.decline_reasons.*`  
**Expected List Message Structure:**

**Title:** `¿Por qué no por ahora?`  
**Body:** `Me ayudaría saber qué te detiene`  
**Button Label:** `Ver opciones` (12 characters — within 20-char limit)

**Options (6 total):**
1. Estoy muy ocupado
2. No entiendo qué es
3. No sé si vale pena
4. No me gusta WhatsApp
5. Tengo suficientes
6. Otro motivo

**Test Steps:**
1. Continue from Test 1.1 welcome message
2. Respond "Mejor después" or equivalent decline phrase
3. Observe the List Message that Elisa sends

**Verification Checklist:**
- [ ] List Message appears correctly (not as plain text)
- [ ] Title displays: `¿Por qué no por ahora?`
- [ ] Body displays: `Me ayudaría saber qué te detiene`
- [ ] Button displays: `Ver opciones`
- [ ] All 6 options are present in the list
- [ ] Option text matches exactly (no typos)
- [ ] Options are in correct order (1-6 as listed above)
- [ ] Selecting any option returns the closing message
- [ ] Closing message matches: `¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme aquí y con gusto te ayudo. ¡Que te vaya muy bien! — Elisa`
- [ ] Emoji 😊 renders correctly in closing message

**Selected Option (record for database verification):** ___________

**Actual Result:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail  

**Notes/Issues:** ___________________________________________

---

## Section 2: Client Flow Testing

### Test 2.1: C2A Region Detection Greeting with Interpolation

**Flow ID:** C2A  
**Message Key:** `elisa.client.region_detection.greeting`  
**Expected Copy Template:**
```
¡Hola! 👋 Soy Elisa de Trato. Veo que eres de %{state}. ¿Buscas un técnico por allá?
```

**Expected Interpolated Result (example with Veracruz):**
```
¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Veracruz. ¿Buscas un técnico por allá?
```

**Test Steps:**
1. Use a test phone number with a Mexican area code that maps to a known state (e.g., Veracruz: 229)
2. Send any message to the **client WhatsApp number** (without a valid short_uuid)
3. Observe the region detection greeting that Elisa sends

**Verification Checklist:**
- [ ] Message displays with correct structure
- [ ] Emoji 👋 renders correctly
- [ ] State name is correctly interpolated (e.g., "Veracruz", "Ciudad de México")
- [ ] State name matches the phone number's area code region
- [ ] Grammar is correct around interpolated state name
- [ ] No interpolation syntax visible (no `%{state}` in message)
- [ ] Punctuation is correct (period after state name)
- [ ] Message tone is friendly and conversational

**Detected State (record):** ___________________________________________

**Actual Message Received:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail  

**Notes/Issues:** ___________________________________________

---

### Test 2.2: C5A Emergency Alerts to Both Client and Provider

**Flow ID:** C5A  
**Message Keys:**
- `elisa.client.emergency.client_alert`
- `elisa.client.emergency.provider_alert`

#### Part A: Client Emergency Alert

**Expected Copy Template:**
```
🚨 %{name}, esto suena urgente. Aléjate del panel y llama a %{provider_name} AHORA: 📞 %{phone}. Si hay riesgo de incendio: llama al 911.
```

**Expected Interpolated Result (example):**
```
🚨 María, esto suena urgente. Aléjate del panel y llama a Miguel AHORA: 📞 +52 229 123 4567. Si hay riesgo de incendio: llama al 911.
```

**Test Steps:**
1. Start a client conversation on the **client WhatsApp number**
2. Select a provider and proceed to conversation stage
3. Send an emergency keyword message (e.g., "Hay chispas saliendo del panel")
4. Observe the emergency alert sent to the **client**

**Verification Checklist:**
- [ ] Client receives emergency alert message
- [ ] Emoji 🚨 renders correctly at start
- [ ] Client name is correctly interpolated (e.g., "María")
- [ ] Provider name is correctly interpolated (e.g., "Miguel")
- [ ] Provider phone is correctly formatted (e.g., "+52 229 123 4567")
- [ ] Phone emoji 📞 renders correctly
- [ ] Grammar is correct ("Aléjate" = informal imperative, appropriate for emergency)
- [ ] Message conveys urgency clearly
- [ ] 911 reference is present and correct

**Client Name (record):** ___________________________________________  
**Provider Name (record):** ___________________________________________  
**Provider Phone (record):** ___________________________________________

**Actual Client Message:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail  

**Notes/Issues:** ___________________________________________

---

#### Part B: Provider Emergency Alert

**Expected Copy Template:**
```
🚨 URGENTE: Tu cliente %{name} reporta %{keyword}. Su número: 📞 %{phone}. Llámale de inmediato.
```

**Expected Interpolated Result (example):**
```
🚨 URGENTE: Tu cliente María reporta chispas. Su número: 📞 +52 229 987 6543. Llámale de inmediato.
```

**Test Steps:**
1. Using the same emergency scenario from Part A
2. Observe the emergency alert sent to the **provider** on the provider WhatsApp number

**Verification Checklist:**
- [ ] Provider receives emergency alert message
- [ ] Provider receives alert immediately (within 2-3 seconds of client message)
- [ ] Emoji 🚨 renders correctly at start
- [ ] "URGENTE" is in all caps for emphasis
- [ ] Client name is correctly interpolated (e.g., "María")
- [ ] Detected keyword is correctly interpolated (e.g., "chispas", "humo", "fuego")
- [ ] Client phone is correctly formatted (e.g., "+52 229 987 6543")
- [ ] Phone emoji 📞 renders correctly
- [ ] Grammar is correct ("Llámale" = gender-neutral imperative)
- [ ] Message conveys urgency to provider

**Client Name (record):** ___________________________________________  
**Detected Keyword (record):** ___________________________________________  
**Client Phone (record):** ___________________________________________

**Actual Provider Message:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail  

**Notes/Issues:** ___________________________________________

---

### Test 2.3: C7A Rating List Message (5 Star Options)

**Flow ID:** C7A  
**Message Key:** `elisa.client.list_messages.ratings.*`  
**Expected List Message Structure:**

**Title:** `¿Cómo calificarías el trabajo?`  
**Body:** `Tu opinión ayuda a otros clientes`  
**Button Label:** `Ver opciones` (12 characters — within 20-char limit)

**Options (5 total):**
1. ⭐⭐⭐⭐⭐ Excelente
2. ⭐⭐⭐⭐ Muy bueno
3. ⭐⭐⭐ Bueno
4. ⭐⭐ Regular
5. ⭐ Malo

**Test Steps:**
1. Complete a client conversation flow through appointment completion
2. Trigger the review collection flow (C7A)
3. Observe the rating List Message that Elisa sends

**Verification Checklist:**
- [ ] List Message appears correctly (not as plain text)
- [ ] Title displays: `¿Cómo calificarías el trabajo?`
- [ ] Body displays: `Tu opinión ayuda a otros clientes`
- [ ] Button displays: `Ver opciones`
- [ ] All 5 rating options are present
- [ ] Star emojis (⭐) render correctly in all options
- [ ] Each option has correct number of stars (5, 4, 3, 2, 1)
- [ ] Rating labels match exactly (Excelente, Muy bueno, Bueno, Regular, Malo)
- [ ] Options are in descending order (5 stars → 1 star)
- [ ] Selecting any option returns acknowledgment message
- [ ] Acknowledgment matches template: `¡Gracias por tu calificación de %{rating} ⭐!`
- [ ] Rating number is correctly interpolated in acknowledgment

**Selected Rating (record):** ___________________________________________

**Acknowledgment Message Received:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail  

**Notes/Issues:** ___________________________________________

---

## Section 3: Cross-Cutting Concerns

### Test 3.1: Emoji Rendering Verification

**Purpose:** Verify that all emojis used in Elisa messages render correctly across WhatsApp platforms (iOS, Android, Web)

**Emojis to Test:**

| Emoji | Unicode | Context | Message Key | Status |
|-------|---------|---------|-------------|--------|
| 👋 | U+1F44B | Welcome/greetings | `provider.onboarding.welcome`, `client.region_detection.greeting` | [ ] Pass [ ] Fail |
| 😊 | U+1F60A | Friendly closing | `provider.onboarding.decline_closing` | [ ] Pass [ ] Fail |
| 🎉 | U+1F389 | Celebration | `provider.onboarding.name_prompt` | [ ] Pass [ ] Fail |
| 📸 | U+1F4F8 | Photo acknowledgment | `provider.photos.profile_ack` | [ ] Pass [ ] Fail |
| 📋 | U+1F4CB | Appointment header | `client.appointment.notification_header` | [ ] Pass [ ] Fail |
| 👤 | U+1F464 | Client field label | `client.appointment.notification_fields.client` | [ ] Pass [ ] Fail |
| 📱 | U+1F4F1 | Phone field label | `client.appointment.notification_fields.phone` | [ ] Pass [ ] Fail |
| 🔧 | U+1F527 | Service field label | `client.appointment.notification_fields.service` | [ ] Pass [ ] Fail |
| 📍 | U+1F4CD | Address field label | `client.appointment.notification_fields.address` | [ ] Pass [ ] Fail |
| 📅 | U+1F4C5 | Date field label | `client.appointment.notification_fields.date` | [ ] Pass [ ] Fail |
| ⏱ | U+23F1 | Duration field label | `client.appointment.notification_fields.duration` | [ ] Pass [ ] Fail |
| 🚨 | U+1F6A8 | Emergency alerts | `client.emergency.client_alert`, `client.emergency.provider_alert` | [ ] Pass [ ] Fail |
| 📞 | U+1F4DE | Phone number in alerts | `client.emergency.client_alert`, `client.emergency.provider_alert` | [ ] Pass [ ] Fail |
| ⭐ | U+2B50 | Star ratings | `client.list_messages.ratings.options` | [ ] Pass [ ] Fail |
| 💬 | U+1F4AC | Comment request | `client.review.comment_request` | [ ] Pass [ ] Fail |
| 🙏 | U+1F64F | Thank you closing | `client.review.completion` | [ ] Pass [ ] Fail |

**Testing Platform(s):**
- [ ] WhatsApp Web (browser: _______________)
- [ ] WhatsApp iOS (version: _______________)
- [ ] WhatsApp Android (version: _______________)

**Verification Checklist:**
- [ ] All emojis display correctly (not as boxes or question marks)
- [ ] Emojis maintain consistent size and style within WhatsApp
- [ ] Emojis do not break message layout or formatting
- [ ] Multiple emojis in sequence display correctly (e.g., ⭐⭐⭐⭐⭐)
- [ ] Emojis appear before/after text as intended (spacing is correct)

**Notes/Issues:** ___________________________________________

---

## Section 4: Additional Message Validation

### Test 4.1: Multiline Message Formatting

**Purpose:** Verify that multiline messages maintain proper formatting in WhatsApp

**Test Cases:**

#### Test 4.1a: Appointment Notification (C4B)

**Expected Structure:**
```
📋 *Nueva cita agendada*
👤 Cliente: [name]
📱 Teléfono: [phone]
🔧 Servicio: [service]
📍 Dirección: [address]
📅 Fecha: [date]
⏱ Duración estimada: [duration]

¿Confirmas esta cita? Responde *sí* o propón otro horario.
```

**Verification:**
- [ ] All lines display correctly (no text wrapping issues)
- [ ] Field labels align properly with values
- [ ] Bold formatting (*Nueva cita agendada*) renders correctly
- [ ] Blank line separates header from footer
- [ ] Bold text (*sí*) renders in footer

**Status:** [ ] Pass  [ ] Fail

---

#### Test 4.1b: Capabilities List (P18A-G)

**Expected Structure:**
```
Soy Elisa y te cuento lo que puedo hacer por ti 👇

📅 *Agenda:* [description]

💰 *Cobros y gastos:* [description]

📋 *Pendientes:* [description]

[etc.]
```

**Verification:**
- [ ] Each capability section is separated by blank line
- [ ] Bold formatting on capability titles renders correctly
- [ ] Emoji bullets display correctly at start of each line
- [ ] Text wrapping is clean and readable

**Status:** [ ] Pass  [ ] Fail

**Notes/Issues:** ___________________________________________

---

## Section 5: Interpolation Validation

### Test 5.1: Variable Interpolation Correctness

**Purpose:** Verify that all dynamic values are correctly interpolated into messages with proper Spanish grammar

**Test Cases:**

| Message Key | Variable(s) | Expected Grammar | Test Value | Status |
|-------------|-------------|------------------|------------|--------|
| `provider.onboarding.greeting` | `name` | "Mucho gusto, [name] 👋" | "Miguel" → "Mucho gusto, Miguel 👋" | [ ] Pass [ ] Fail |
| `provider.completion.message` | `name`, `profile_url`, `assistant_link` | "¡Listo, [name]! Tu perfil..." | Test with real URLs | [ ] Pass [ ] Fail |
| `client.region_detection.greeting` | `state` | "Veo que eres de [state]." | "Veracruz" → "Veo que eres de Veracruz." | [ ] Pass [ ] Fail |
| `client.appointment.no_workday` | `name` | "[name] no tiene su agenda..." | "Miguel" → "Miguel no tiene su agenda..." | [ ] Pass [ ] Fail |
| `client.emergency.client_alert` | `name`, `provider_name`, `phone` | "[name], esto suena urgente. Aléjate... llama a [provider_name]... [phone]" | Test with real names and phone | [ ] Pass [ ] Fail |
| `client.review.rating_ack` | `rating` | "calificación de [rating] ⭐" | 5 → "calificación de 5 ⭐" | [ ] Pass [ ] Fail |
| `client.review.comment_request` | `name` | "le ayuda mucho a [name]" | "Miguel" → "le ayuda mucho a Miguel" | [ ] Pass [ ] Fail |

**Common Interpolation Errors to Check:**
- [ ] No interpolation syntax visible in messages (no `%{variable}` in output)
- [ ] No missing spaces around interpolated values
- [ ] No extra spaces around interpolated values
- [ ] No null/nil values displayed (e.g., "Mucho gusto,  👋" with blank name)
- [ ] Articles and prepositions grammatically correct (e.g., "de Veracruz", not "de de Veracruz")

**Notes/Issues:** ___________________________________________

---

## Section 6: List Message Button Label Validation

### Test 6.1: Button Label Length Compliance

**Purpose:** Verify that all List Message button labels comply with WhatsApp's 20-character limit

**List Messages to Validate:**

| List Message | Button Label | Character Count | Limit | Status |
|--------------|--------------|-----------------|-------|--------|
| Decline Reasons (P1B) | `Ver opciones` | 12 | ≤20 | [ ] Pass [ ] Fail |
| Price Range (P4) | `Ver opciones` | 12 | ≤20 | [ ] Pass [ ] Fail |
| Experience (P5) | `Ver opciones` | 12 | ≤20 | [ ] Pass [ ] Fail |
| Financial Summary (P17) | `Ver opciones` | 12 | ≤20 | [ ] Pass [ ] Fail |
| Ratings (C7A) | `Ver opciones` | 12 | ≤20 | [ ] Pass [ ] Fail |

**Verification:**
- [ ] All button labels display completely (not truncated)
- [ ] All button labels are clickable and functional
- [ ] Button labels are consistent across all List Messages
- [ ] No custom labels exceed 20 characters

**Status:** [ ] Pass  [ ] Fail

**Notes/Issues:** ___________________________________________

---

## Section 7: Edge Cases and Error Handling

### Test 7.1: Invalid Rating Input (C7A/C7C)

**Purpose:** Verify error message displays correctly when invalid rating is provided

**Expected Error Message:**
```
Por favor responde con un número del 1 al 5 para tu calificación ⭐
```

**Test Steps:**
1. Trigger rating flow (C7A)
2. Instead of selecting from List Message, type invalid input (e.g., "6", "0", "bueno")
3. Observe error message

**Verification:**
- [ ] Error message displays exactly as specified
- [ ] Star emoji ⭐ renders correctly
- [ ] Message is clear and actionable
- [ ] User can retry with valid input

**Status:** [ ] Pass  [ ] Fail

---

## Section 8: YAML Source Verification

### Test 8.1: Match Against KIRO_PROMPT_FLOWS_v5.md

**Purpose:** Final verification that all tested messages match the official v5 specification

**Instructions:**
1. Open KIRO_PROMPT_FLOWS_v5.md
2. For each tested message, compare the received WhatsApp message against the spec
3. Check for exact match (punctuation, emojis, spacing, wording)

**Critical Messages to Verify:**

- [ ] P1A Welcome: Matches v5 spec exactly
- [ ] P1B Decline reasons: All 6 options match v5 spec
- [ ] C2A Region greeting: Template structure matches v5 spec
- [ ] C5A Client alert: Matches v5 spec exactly
- [ ] C5A Provider alert: Matches v5 spec exactly
- [ ] C7A Rating options: All 5 options match v5 spec

**Discrepancies Found:** ___________________________________________

**Status:** [ ] Pass  [ ] Fail

---

## Test Summary

### Overall Results

**Total Tests:** 8 sections, 20+ individual test cases  
**Tests Passed:** _____  
**Tests Failed:** _____  
**Tests Skipped:** _____

### Critical Issues Found

1. ___________________________________________
2. ___________________________________________
3. ___________________________________________

### Non-Critical Issues Found

1. ___________________________________________
2. ___________________________________________
3. ___________________________________________

### Recommendations

1. ___________________________________________
2. ___________________________________________
3. ___________________________________________

---

## Sign-Off

**Tester Name:** _____________________  
**Date:** _____________________  
**Signature:** _____________________

**Approval Status:**
- [ ] All critical tests passed — ready for production
- [ ] Minor issues found — fix before production
- [ ] Major issues found — requires rework and re-testing

**Approved By:** _____________________  
**Date:** _____________________  
**Signature:** _____________________

---

## Appendix: Testing Environment Details

### Provider Test Number
- **Phone Number:** ___________________________________________
- **Phone Number ID:** ___________________________________________
- **Meta API Status:** [ ] Connected  [ ] Issues

### Client Test Number
- **Phone Number:** ___________________________________________
- **Phone Number ID:** ___________________________________________
- **Meta API Status:** [ ] Connected  [ ] Issues

### Test Database
- **Environment:** [ ] Development  [ ] Staging  [ ] Production (DO NOT TEST IN PROD)
- **Database Name:** ___________________________________________
- **Test Providers Created:** _____
- **Test Clients Created:** _____

### Testing Tools
- **WhatsApp Platform:** ___________________________________________
- **Device/Browser:** ___________________________________________
- **Screen Recording:** [ ] Yes  [ ] No  (File: _______________)
- **Screenshots Captured:** [ ] Yes  [ ] No  (Count: _______)

---

**End of Manual Testing Checklist**
