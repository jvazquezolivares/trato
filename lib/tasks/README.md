# Rake Tasks de Desarrollo

Este directorio contiene tareas rake útiles para el desarrollo de Trato.

## Tareas Disponibles

### `dev:reset_onboarding`

Limpia completamente la base de datos y Redis para permitir un onboarding fresco desde cero.

**Uso:**
```bash
bundle exec rake dev:reset_onboarding
```

**Qué hace:**
- Elimina todos los providers, clientes, conversaciones, mensajes, trabajos, citas, etc.
- Limpia los estados de onboarding en Redis
- Reinicia los IDs de las tablas (RESTART IDENTITY)
- Muestra estadísticas finales

**Cuándo usarlo:**
- Cuando quieres probar el flujo de onboarding desde cero
- Después de cambios importantes en el flujo de onboarding
- Para limpiar datos de prueba

**Seguridad:**
- ⚠️ Solo funciona en ambiente de desarrollo
- ⚠️ Elimina TODOS los datos de la base de datos

---

### `dev:delete_provider[phone]`

Elimina un provider específico y todos sus datos relacionados por número de teléfono.

**Uso:**
```bash
# Con número sin formato
bundle exec rake dev:delete_provider[5212211234567]

# Con formato (espacios, guiones, paréntesis, +)
bundle exec rake dev:delete_provider[+52 221 123 4567]
bundle exec rake dev:delete_provider[52-221-123-4567]
```

**Qué hace:**
- Busca el provider por número de teléfono (normaliza el formato automáticamente)
- Muestra información del provider encontrado
- Muestra conteo de datos relacionados que serán eliminados
- Pide confirmación antes de eliminar
- Elimina el provider y todos sus datos relacionados (cascade)
- Limpia estados de Redis para ese provider

**Datos que elimina:**
- Provider
- Categorías del provider
- Conversaciones
- Mensajes
- Trabajos
- Citas
- Transacciones
- Reseñas
- Fotos
- Posts de redes sociales
- Relaciones con clientes

**Cuándo usarlo:**
- Cuando quieres eliminar un provider específico sin afectar otros
- Para limpiar un provider de prueba
- Cuando un provider tiene datos incorrectos y quieres que haga onboarding de nuevo

**Seguridad:**
- ⚠️ Solo funciona en ambiente de desarrollo
- ⚠️ Pide confirmación antes de eliminar
- ⚠️ La eliminación es permanente (no se puede deshacer)

**Ejemplo de uso:**
```bash
$ bundle exec rake dev:delete_provider[5212211234567]

🔍 Buscando provider con teléfono: 5212211234567

📋 Provider encontrado:
  Nombre: Javier Arturo Vázquez Olivares
  Teléfono: 5212211234567
  UUID: a53529af
  Ciudad: Puebla

📊 Datos relacionados que serán eliminados:
  Categorías: 2
  Conversaciones: 1
  Trabajos: 0
  Citas: 0
  Fotos: 0
  Reseñas: 0

⚠️  ¿Estás seguro de eliminar este provider? (y/N): y

🗑️  Eliminando provider y datos relacionados...
✅ Provider eliminado exitosamente

📊 Estado actual:
  Providers restantes: 0
```

---

### `dev:stats`

Muestra estadísticas actuales de la base de datos.

**Uso:**
```bash
bundle exec rake dev:stats
```

**Qué muestra:**
- Conteo de providers
- Conteo de clientes
- Conteo de conversaciones
- Conteo de mensajes
- Conteo de trabajos
- Conteo de citas
- Conteo de reseñas
- Conteo de fotos
- Lista de providers registrados (si hay alguno)

**Cuándo usarlo:**
- Para verificar el estado actual de la base de datos
- Después de ejecutar `reset_onboarding` o `delete_provider`
- Para ver qué providers están registrados

**Ejemplo de salida:**
```bash
$ bundle exec rake dev:stats

📊 Estadísticas de la base de datos:

  Providers: 2
  Clients: 5
  Conversations: 7
  Messages: 45
  Jobs: 3
  Appointments: 2
  Reviews: 1
  Photos: 8

👥 Providers registrados:
  - Javier Arturo Vázquez Olivares (5212211234567) - Puebla
  - Miguel García (5212211234568) - Veracruz
```

---

## Flujo de Trabajo Típico

### Probar onboarding desde cero
```bash
# 1. Limpiar todo
bundle exec rake dev:reset_onboarding

# 2. Enviar mensaje desde tu WhatsApp al número de Trato
# 3. Completar el onboarding

# 4. Ver estadísticas
bundle exec rake dev:stats
```

### Eliminar un provider específico
```bash
# 1. Ver qué providers existen
bundle exec rake dev:stats

# 2. Eliminar uno específico
bundle exec rake dev:delete_provider[5212211234567]

# 3. Verificar que se eliminó
bundle exec rake dev:stats
```

### Probar múltiples onboardings
```bash
# 1. Hacer primer onboarding
# (enviar mensaje desde número 1)

# 2. Ver estadísticas
bundle exec rake dev:stats

# 3. Hacer segundo onboarding
# (enviar mensaje desde número 2)

# 4. Ver estadísticas
bundle exec rake dev:stats

# 5. Eliminar el primero si quieres
bundle exec rake dev:delete_provider[numero1]
```

---

## Notas Importantes

1. **Solo desarrollo**: Todas estas tareas solo funcionan en ambiente de desarrollo por seguridad.

2. **Confirmación**: `delete_provider` pide confirmación antes de eliminar.

3. **Normalización de teléfonos**: `delete_provider` normaliza automáticamente el formato del teléfono, así que puedes usar cualquier formato.

4. **Cascade delete**: Al eliminar un provider, todos sus datos relacionados se eliminan automáticamente gracias a las relaciones `dependent: :destroy` en el modelo.

5. **Redis**: Ambos comandos limpian los estados de Redis para evitar problemas con estados obsoletos.

6. **Transacciones**: `delete_provider` usa transacciones para asegurar que todo se elimine correctamente o nada se elimine si hay un error.

---

## Troubleshooting

### Error: "Este comando solo puede ejecutarse en desarrollo"
**Solución:** Verifica que estés en ambiente de desarrollo:
```bash
echo $RAILS_ENV  # Debe estar vacío o ser "development"
```

### Error: "No se encontró ningún provider con ese número"
**Solución:** 
1. Verifica el número con `rake dev:stats`
2. Asegúrate de usar el formato correcto (sin espacios en los corchetes)
3. El número debe estar en la base de datos

### Error: "StrictLoadingViolationError"
**Solución:** Usa `delete_provider` en lugar de intentar eliminar manualmente con `Provider.destroy_all`

---

## Agregar Nuevas Tareas

Para agregar nuevas tareas de desarrollo, edita `lib/tasks/dev.rake`:

```ruby
namespace :dev do
  desc "Descripción de tu tarea"
  task mi_tarea: :environment do
    # Tu código aquí
  end
end
```

Luego verifica que aparezca:
```bash
bundle exec rake -T dev
```
