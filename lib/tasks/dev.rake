# frozen_string_literal: true

# Development tasks for Trato
#
# Usage:
#   bundle exec rake dev:reset_onboarding          # Clean all data for fresh onboarding
#   bundle exec rake dev:stats                     # Show database statistics
#   bundle exec rake dev:delete_provider[phone]    # Delete specific provider by phone
#
# Examples:
#   bundle exec rake dev:reset_onboarding
#   bundle exec rake dev:stats
#   bundle exec rake dev:delete_provider[5212211234567]
#   bundle exec rake dev:delete_provider[+52 221 123 4567]  # Works with formatting

namespace :dev do
  desc "Reset all data for fresh onboarding (development only)"
  task reset_onboarding: :environment do
    unless Rails.env.development?
      puts "❌ Este comando solo puede ejecutarse en desarrollo"
      exit 1
    end

    puts "🗑️  Limpiando base de datos..."

    # Truncate all tables related to providers and clients
    ActiveRecord::Base.connection.execute(
      "TRUNCATE TABLE providers, provider_categories, provider_clients, " \
      "work_days, tasks, appointments, jobs, transactions, reviews, " \
      "conversations, messages, photos, social_posts, clients " \
      "RESTART IDENTITY CASCADE"
    )

    puts "✅ Base de datos limpiada"

    # Clean Redis onboarding states
    puts "🗑️  Limpiando estados de Redis..."
    REDIS.keys("onboarding_state:*").each { |key| REDIS.del(key) }
    REDIS.keys("search_state:*").each { |key| REDIS.del(key) }
    puts "✅ Redis limpiado"

    # Show final state
    puts ""
    puts "📊 Estado final:"
    puts "  Providers: #{Provider.count}"
    puts "  Clients: #{Client.count}"
    puts "  Conversations: #{Conversation.count}"
    puts "  Messages: #{Message.count}"
    puts ""
    puts "✅ Sistema listo para nuevo onboarding"
    puts ""
    puts "💡 Para probar, envía un mensaje desde un número nuevo al WhatsApp de Trato"
  end

  desc "Delete a specific provider and all related data by phone number"
  task :delete_provider, [:phone] => :environment do |_t, args|
    unless Rails.env.development?
      puts "❌ Este comando solo puede ejecutarse en desarrollo"
      exit 1
    end

    unless args[:phone]
      puts "❌ Error: Debes proporcionar un número de teléfono"
      puts ""
      puts "Uso:"
      puts "  bundle exec rake dev:delete_provider[5212211234567]"
      puts "  bundle exec rake dev:delete_provider[+52 221 123 4567]"
      puts ""
      exit 1
    end

    # Normalize phone number (remove spaces, dashes, parentheses, plus sign)
    normalized_phone = args[:phone].gsub(/[\s\-\(\)\+]/, "")

    puts "🔍 Buscando provider con teléfono: #{normalized_phone}"

    provider = Provider.find_by(phone: normalized_phone)

    unless provider
      puts "❌ No se encontró ningún provider con ese número"
      puts ""
      puts "📊 Providers existentes:"
      Provider.all.each do |p|
        puts "  - #{p.name} (#{p.phone})"
      end
      exit 1
    end

    puts ""
    puts "📋 Provider encontrado:"
    puts "  Nombre: #{provider.name}"
    puts "  Teléfono: #{provider.phone}"
    puts "  UUID: #{provider.short_uuid}"
    puts "  Ciudad: #{provider.city}"
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

    print "⚠️  ¿Estás seguro de eliminar este provider? (y/N): "
    confirmation = $stdin.gets.chomp.downcase

    unless confirmation == "y" || confirmation == "yes"
      puts "❌ Operación cancelada"
      exit 0
    end

    puts ""
    puts "🗑️  Eliminando provider y datos relacionados..."

    # Delete provider (cascade will handle related records)
    ActiveRecord::Base.transaction do
      provider.destroy!
    end

    # Clean Redis states for this provider
    REDIS.keys("onboarding_state:#{normalized_phone}").each { |key| REDIS.del(key) }

    puts "✅ Provider eliminado exitosamente"
    puts ""
    puts "📊 Estado actual:"
    puts "  Providers restantes: #{Provider.count}"
    puts ""
  end

  desc "Show current database stats"
  task stats: :environment do
    puts "📊 Estadísticas de la base de datos:"
    puts ""
    puts "  Providers: #{Provider.count}"
    puts "  Clients: #{Client.count}"
    puts "  Conversations: #{Conversation.count}"
    puts "  Messages: #{Message.count}"
    puts "  Jobs: #{Job.count}"
    puts "  Appointments: #{Appointment.count}"
    puts "  Reviews: #{Review.count}"
    puts "  Photos: #{Photo.count}"
    puts ""

    if Provider.any?
      puts "👥 Providers registrados:"
      Provider.all.each do |provider|
        puts "  - #{provider.name} (#{provider.phone}) - #{provider.city}"
      end
      puts ""
    end
  end
end
