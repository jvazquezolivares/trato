# frozen_string_literal: true

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
  end
end
