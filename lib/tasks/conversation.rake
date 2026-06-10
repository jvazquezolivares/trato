# frozen_string_literal: true

# Conversation management tasks for Trato
#
# Usage:
#   bundle exec rake conversation:reset_provider[phone]     # Reset provider conversation
#   bundle exec rake conversation:reset_client[phone]       # Reset client conversation
#   bundle exec rake conversation:info[phone]               # Show conversation info
#
# Examples:
#   bundle exec rake conversation:reset_provider[5212211234567]
#   bundle exec rake conversation:reset_client[+52 221 123 4567]
#   bundle exec rake conversation:info[5212211234567]
#
# Production usage (Railway):
#   railway run bundle exec rake conversation:reset_provider[5212292272709]
#   railway run bundle exec rake conversation:reset_client[5215611661032]
#
# Note: In production, only whitelisted phone numbers can be reset for safety.

# Whitelist of phone numbers allowed to reset conversations in production
# These are typically test/development numbers or internal team numbers
PRODUCTION_WHITELIST = %w[
  5212292272709
  5215611661032
].freeze

# Helper method to normalize and check if phone is whitelisted for production operations
def check_production_whitelist(phone)
  normalized = phone.gsub(/[\s\-\(\)\+]/, "")

  unless PRODUCTION_WHITELIST.include?(normalized)
    puts "❌ Error: Este número no está en la whitelist de producción"
    puts ""
    puts "Números permitidos:"
    PRODUCTION_WHITELIST.each { |p| puts "  - #{p}" }
    puts ""
    puts "Si necesitas agregar este número a la whitelist, edita:"
    puts "  trato/lib/tasks/conversation.rake"
    puts ""
    exit 1
  end

  normalized
end

namespace :conversation do

  desc "Show conversation information for a specific phone number"
  task :info, [:phone] => :environment do |_t, args|
    unless args[:phone]
      puts "❌ Error: Debes proporcionar un número de teléfono"
      puts ""
      puts "Uso:"
      puts "  bundle exec rake conversation:info[5212211234567]"
      puts "  bundle exec rake conversation:info[+52 221 123 4567]"
      puts ""
      exit 1
    end

    # Normalize phone number (remove spaces, dashes, parentheses, plus sign)
    normalized_phone = args[:phone].gsub(/[\s\-\(\)\+]/, "")

    puts "🔍 Buscando información para: #{normalized_phone}"
    puts "🌍 Ambiente: #{Rails.env}"
    puts ""

    # Check Redis states
    onboarding_key = "onboarding_state:#{normalized_phone}"
    search_key = "search_state:#{normalized_phone}"

    onboarding_state = REDIS.get(onboarding_key)
    search_state = REDIS.get(search_key)

    puts "📦 Estados en Redis:"
    if onboarding_state
      state = JSON.parse(onboarding_state)
      puts "  ✓ onboarding_state encontrado:"
      puts "    Stage: #{state['stage']}"
      puts "    Data keys: #{state['data']&.keys&.join(', ')}"
    else
      puts "  ✗ No hay onboarding_state"
    end

    if search_state
      puts "  ✓ search_state encontrado"
    else
      puts "  ✗ No hay search_state"
    end
    puts ""

    # Check if Provider exists
    provider = Provider.find_by(phone: normalized_phone)

    if provider
      puts "👤 Provider encontrado:"
      puts "  ID: #{provider.id}"
      puts "  Nombre: #{provider.name}"
      puts "  Teléfono: #{provider.phone}"
      puts "  UUID: #{provider.short_uuid}"
      puts "  Ciudad: #{provider.city}"
      puts "  Slug: #{provider.slug}"
      puts ""

      # Check conversations as provider
      provider_conversations = provider.conversations
      if provider_conversations.any?
        puts "💬 Conversaciones como Provider (#{provider_conversations.count}):"
        provider_conversations.each do |conv|
          client_info = conv.client ? "Cliente: #{conv.client.name}" : "Sin cliente"
          puts "  - ID: #{conv.id}, Stage: #{conv.stage}, Messages: #{conv.messages.count}, #{client_info}"
        end
        puts ""
      else
        puts "💬 No hay conversaciones como provider"
        puts ""
      end
    else
      puts "👤 No se encontró Provider con ese número"
      puts ""
    end

    # Check if Client exists
    client = Client.find_by(phone: normalized_phone)

    if client
      puts "👥 Cliente encontrado:"
      puts "  ID: #{client.id}"
      puts "  Nombre: #{client.name || 'Sin nombre'}"
      puts "  Teléfono: #{client.phone}"
      puts ""
    else
      puts "👥 No se encontró Cliente con ese número"
      puts ""
    end

    # Check conversations as client
    client_conversations = Conversation.where(phone: normalized_phone, role: "client")
    if client_conversations.any?
      puts "💬 Conversaciones como Cliente (#{client_conversations.count}):"
      client_conversations.each do |conv|
        provider_info = conv.provider ? "Provider: #{conv.provider.name}" : "Sin provider"
        puts "  - ID: #{conv.id}, Stage: #{conv.stage}, Messages: #{conv.messages.count}, #{provider_info}"
      end
      puts ""
    else
      puts "💬 No hay conversaciones como cliente"
      puts ""
    end
  end

  desc "Reset provider conversation state (whitelist-protected in production)"
  task :reset_provider, [:phone] => :environment do |_t, args|
    unless args[:phone]
      puts "❌ Error: Debes proporcionar un número de teléfono"
      puts ""
      puts "Uso:"
      puts "  bundle exec rake conversation:reset_provider[5212211234567]"
      puts "  bundle exec rake conversation:reset_provider[+52 221 123 4567]"
      puts ""
      puts "Railway:"
      puts "  railway run bundle exec rake conversation:reset_provider[5212292272709]"
      puts ""
      exit 1
    end

    # In production, check whitelist
    normalized_phone = if Rails.env.production?
                        check_production_whitelist(args[:phone])
                      else
                        args[:phone].gsub(/[\s\-\(\)\+]/, "")
                      end

    puts "🔍 Buscando conversación de PROVIDER para: #{normalized_phone}"
    puts "🌍 Ambiente: #{Rails.env}"
    puts ""

    # Check Redis state
    redis_key = "onboarding_state:#{normalized_phone}"
    redis_state = REDIS.get(redis_key)

    # Check if Provider exists
    provider = Provider.find_by(phone: normalized_phone)

    # Show what will be reset
    puts "📊 Estado actual:"
    if redis_state
      state = JSON.parse(redis_state)
      puts "  ✓ Redis onboarding_state encontrado (stage: #{state['stage']})"
    else
      puts "  ✗ No hay Redis onboarding_state"
    end

    if provider
      conversations = provider.conversations
      messages_count = conversations.sum { |c| c.messages.count }
      puts "  ✓ Provider encontrado: #{provider.name}"
      puts "  ✓ Conversaciones: #{conversations.count}"
      puts "  ✓ Mensajes totales: #{messages_count}"
    else
      puts "  ✗ No hay Provider"
    end
    puts ""

    # No need for extra confirmation in production since whitelist is already checked
    unless Rails.env.production?
      print "⚠️  ¿Continuar con el reset? (y/N): "
      confirmation = $stdin.gets.chomp.downcase

      unless confirmation == "y" || confirmation == "yes"
        puts "❌ Operación cancelada"
        exit 0
      end
      puts ""
    end

    # Start reset process
    puts "🗑️  Iniciando reset de conversación de provider..."
    puts ""

    # 1. Clean Redis state
    if redis_state
      REDIS.del(redis_key)
      puts "✅ Redis onboarding_state eliminado"
    else
      puts "⏭️  No había Redis onboarding_state que limpiar"
    end

    # 2. Delete conversations and messages
    if provider
      conversations = provider.conversations
      messages_count = conversations.sum { |c| c.messages.count }

      ActiveRecord::Base.transaction do
        conversations.each do |conversation|
          conversation.messages.destroy_all
          conversation.destroy!
        end
      end

      puts "✅ #{conversations.count} conversaciones eliminadas"
      puts "✅ #{messages_count} mensajes eliminados"
    else
      puts "⏭️  No había conversaciones que eliminar"
    end

    puts ""
    puts "✅ Reset de provider completado exitosamente"
    puts ""
    puts "📊 Estado final:"
    puts "  Redis onboarding_state: #{REDIS.get(redis_key).present? ? 'Presente' : 'Limpio'}"
    if provider
      puts "  Provider: #{provider.name} (#{provider.phone})"
      puts "  Conversaciones: #{provider.conversations.count}"
    else
      puts "  Provider: No existe"
    end
    puts ""
    puts "💡 El provider puede ahora enviar un mensaje desde #{normalized_phone}"
    puts "   y comenzará una conversación nueva desde cero"
    puts ""
  end

  desc "Reset client conversation state (whitelist-protected in production)"
  task :reset_client, [:phone] => :environment do |_t, args|
    unless args[:phone]
      puts "❌ Error: Debes proporcionar un número de teléfono"
      puts ""
      puts "Uso:"
      puts "  bundle exec rake conversation:reset_client[5212211234567]"
      puts "  bundle exec rake conversation:reset_client[+52 221 123 4567]"
      puts ""
      puts "Railway:"
      puts "  railway run bundle exec rake conversation:reset_client[5215611661032]"
      puts ""
      exit 1
    end

    # In production, check whitelist
    normalized_phone = if Rails.env.production?
                        check_production_whitelist(args[:phone])
                      else
                        args[:phone].gsub(/[\s\-\(\)\+]/, "")
                      end

    puts "🔍 Buscando conversación de CLIENTE para: #{normalized_phone}"
    puts "🌍 Ambiente: #{Rails.env}"
    puts ""

    # Check Redis states (search_state for clients)
    search_state_key = "search_state:#{normalized_phone}"
    search_state = REDIS.get(search_state_key)

    # Check if Client exists
    client = Client.find_by(phone: normalized_phone)

    # Find conversations where this phone is the client
    conversations = Conversation.where(phone: normalized_phone, role: "client")

    # Show what will be reset
    puts "📊 Estado actual:"
    if search_state
      puts "  ✓ Redis search_state encontrado"
    else
      puts "  ✗ No hay Redis search_state"
    end

    if client
      puts "  ✓ Cliente encontrado: #{client.name || 'Sin nombre'} (ID: #{client.id})"
    else
      puts "  ✗ No hay registro de Cliente"
    end

    if conversations.any?
      messages_count = conversations.sum { |c| c.messages.count }
      puts "  ✓ Conversaciones como cliente: #{conversations.count}"
      puts "  ✓ Mensajes totales: #{messages_count}"

      # Show providers involved
      provider_names = conversations.map { |c| c.provider&.name }.compact.uniq
      puts "  ✓ Providers involucrados: #{provider_names.join(', ')}"
    else
      puts "  ✗ No hay conversaciones como cliente"
    end
    puts ""

    # No need for extra confirmation in production since whitelist is already checked
    unless Rails.env.production?
      print "⚠️  ¿Continuar con el reset? (y/N): "
      confirmation = $stdin.gets.chomp.downcase

      unless confirmation == "y" || confirmation == "yes"
        puts "❌ Operación cancelada"
        exit 0
      end
      puts ""
    end

    # Start reset process
    puts "🗑️  Iniciando reset de conversación de cliente..."
    puts ""

    # 1. Clean Redis search state
    if search_state
      REDIS.del(search_state_key)
      puts "✅ Redis search_state eliminado"
    else
      puts "⏭️  No había Redis search_state que limpiar"
    end

    # 2. Delete conversations and messages
    if conversations.any?
      messages_count = conversations.sum { |c| c.messages.count }

      ActiveRecord::Base.transaction do
        conversations.each do |conversation|
          conversation.messages.destroy_all
          conversation.destroy!
        end
      end

      puts "✅ #{conversations.count} conversaciones eliminadas"
      puts "✅ #{messages_count} mensajes eliminados"
    else
      puts "⏭️  No había conversaciones que eliminar"
    end

    # 3. Optionally delete client record (commented out - keep client data)
    # if client
    #   client.destroy!
    #   puts "✅ Registro de cliente eliminado"
    # end

    puts ""
    puts "✅ Reset de cliente completado exitosamente"
    puts ""
    puts "📊 Estado final:"
    puts "  Redis search_state: #{REDIS.get(search_state_key).present? ? 'Presente' : 'Limpio'}"
    if client
      puts "  Cliente: #{client.name || 'Sin nombre'} (#{client.phone})"
      puts "    (El registro de cliente se mantiene, solo se eliminaron conversaciones)"
    else
      puts "  Cliente: No existe registro"
    end
    puts "  Conversaciones: #{Conversation.where(phone: normalized_phone, role: 'client').count}"
    puts ""
    puts "💡 El cliente puede ahora enviar un mensaje desde #{normalized_phone}"
    puts "   y comenzará una búsqueda/conversación nueva desde cero"
    puts ""
  end

  desc "Reset conversation and delete provider completely (use with caution)"
  task :delete_provider, [:phone] => :environment do |_t, args|
    unless args[:phone]
      puts "❌ Error: Debes proporcionar un número de teléfono"
      puts ""
      puts "Uso:"
      puts "  bundle exec rake conversation:delete_provider[5212211234567]"
      puts ""
      exit 1
    end

    # Normalize phone number
    normalized_phone = args[:phone].gsub(/[\s\-\(\)\+]/, "")

    puts "🔍 Buscando provider: #{normalized_phone}"
    puts "🌍 Ambiente: #{Rails.env}"
    puts ""

    provider = Provider.find_by(phone: normalized_phone)

    unless provider
      puts "❌ No se encontró ningún provider con ese número"
      puts ""
      exit 1
    end

    puts "📋 Provider encontrado:"
    puts "  Nombre: #{provider.name}"
    puts "  Teléfono: #{provider.phone}"
    puts "  UUID: #{provider.short_uuid}"
    puts ""

    # Show related data counts
    puts "📊 Datos relacionados que serán eliminados:"
    puts "  Categorías: #{provider.provider_categories.count}"
    puts "  Conversaciones: #{provider.conversations.count}"
    puts "  Trabajos: #{provider.jobs.count}"
    puts "  Citas: #{provider.appointments.count}"
    puts "  Fotos: #{provider.photos.count}"
    puts "  Reseñas: #{provider.reviews.count}"
    puts ""

    # Confirm
    if Rails.env.production?
      puts "⚠️  ADVERTENCIA: Estás en PRODUCCIÓN"
      puts "⚠️  Esta acción es IRREVERSIBLE y eliminará TODOS los datos del provider"
      puts ""
      puts "Para confirmar, escribe: 'DELETE #{provider.name}'"
      print "> "

      confirmation = $stdin.gets.chomp
      expected = "DELETE #{provider.name}"

      unless confirmation == expected
        puts "❌ Operación cancelada"
        puts "   (escribiste: '#{confirmation}')"
        puts "   (se esperaba: '#{expected}')"
        exit 0
      end
    else
      print "⚠️  ¿Estás seguro de eliminar este provider? (y/N): "
      confirmation = $stdin.gets.chomp.downcase

      unless confirmation == "y" || confirmation == "yes"
        puts "❌ Operación cancelada"
        exit 0
      end
    end

    puts ""
    puts "🗑️  Eliminando provider y datos relacionados..."

    # Delete provider (cascade will handle related records)
    ActiveRecord::Base.transaction do
      provider.destroy!
    end

    # Clean Redis states
    REDIS.del("onboarding_state:#{normalized_phone}")

    puts "✅ Provider eliminado exitosamente"
    puts ""
  end
end
