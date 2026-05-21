# frozen_string_literal: true

# Manages temporary slot reservations using Redis distributed locks.
# Prevents race conditions when multiple clients try to book the same appointment slot.
#
# Flow:
#   1. Client selects a slot → reserve_slot (5-minute hold)
#   2. Client confirms → confirm_reservation (creates Appointment)
#   3. Client cancels or timeout → slot released automatically
#
# Usage:
#   SlotReservationService.reserve_slot(slot_time, work_day_id, client_phone)
#   SlotReservationService.confirm_reservation(slot_time, work_day_id, client_phone)
class SlotReservationService
  RESERVATION_TTL = 300 # 5 minutes in seconds

  # Attempts to reserve a slot for a client.
  # Returns success: true if reserved, false if already taken.
  #
  # @param slot_time [Time] The appointment slot time
  # @param work_day_id [Integer] The WorkDay ID
  # @param client_phone [String] The client's phone number
  # @return [Hash] { success: Boolean, expires_at: Time, reserved_by: String }
  def self.reserve_slot(slot_time, work_day_id, client_phone)
    redis_key = build_redis_key(work_day_id, slot_time)

    # Try to set reservation (only if key doesn't exist)
    # nx: true → only set if key doesn't exist
    # ex: RESERVATION_TTL → expire after TTL seconds
    reserved = REDIS.set(redis_key, client_phone, nx: true, ex: RESERVATION_TTL)

    if reserved
      Rails.logger.info("[SlotReservationService] Reserved slot #{slot_time} for #{client_phone}")
      {
        success: true,
        expires_at: Time.current + RESERVATION_TTL.seconds
      }
    else
      # Slot already reserved by someone else
      reserved_by = REDIS.get(redis_key)
      Rails.logger.info("[SlotReservationService] Slot #{slot_time} already reserved by #{reserved_by}")
      {
        success: false,
        reserved_by: reserved_by
      }
    end
  end

  # Confirms a reservation and creates the actual Appointment record.
  # Validates that the client has the reservation and the slot is still available in DB.
  #
  # @param slot_time [Time] The appointment slot time
  # @param work_day_id [Integer] The WorkDay ID
  # @param client_phone [String] The client's phone number
  # @param provider [Provider] The provider
  # @param client [Client] The client
  # @return [Appointment, nil] The created appointment or nil if failed
  def self.confirm_reservation(slot_time, work_day_id, client_phone, provider:, client:)
    redis_key = build_redis_key(work_day_id, slot_time)
    reserved_by = REDIS.get(redis_key)

    # Check if reservation expired
    if reserved_by.nil?
      Rails.logger.warn("[SlotReservationService] Reservation expired for #{client_phone} at #{slot_time}")
      return { success: false, reason: :expired }
    end

    # Verify this client has the reservation
    unless reserved_by == client_phone
      Rails.logger.warn("[SlotReservationService] Client #{client_phone} tried to confirm slot reserved by #{reserved_by}")
      return { success: false, reason: :not_owner }
    end

    # Create actual appointment with database lock
    appointment = nil
    ActiveRecord::Base.transaction do
      work_day = WorkDay.lock.find(work_day_id)

      # Double-check slot is still available in DB (not taken by another appointment)
      if slot_taken_in_db?(slot_time, work_day)
        Rails.logger.error("[SlotReservationService] Slot #{slot_time} taken in DB despite Redis reservation")
        REDIS.del(redis_key)
        return { success: false, reason: :db_conflict }
      end

      # Create appointment
      appointment = Appointment.create!(
        work_day: work_day,
        provider: provider,
        client: client,
        scheduled_at: slot_time,
        estimated_duration: 60, # Default 1 hour
        status: "pending"
      )

      Rails.logger.info("[SlotReservationService] Created appointment #{appointment.id} for #{client_phone} at #{slot_time}")
    end

    # Remove reservation from Redis
    REDIS.del(redis_key)

    { success: true, appointment: appointment }
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[SlotReservationService] Failed to create appointment: #{e.message}")
    REDIS.del(redis_key)
    { success: false, reason: :validation_error, error: e.message }
  end

  # Cancels a reservation, releasing the slot for other clients.
  #
  # @param slot_time [Time] The appointment slot time
  # @param work_day_id [Integer] The WorkDay ID
  # @param client_phone [String] The client's phone number
  # @return [Boolean] True if cancelled, false if not found or not owner
  def self.cancel_reservation(slot_time, work_day_id, client_phone)
    redis_key = build_redis_key(work_day_id, slot_time)
    reserved_by = REDIS.get(redis_key)

    # Only allow cancellation by the client who reserved it
    if reserved_by == client_phone
      REDIS.del(redis_key)
      Rails.logger.info("[SlotReservationService] Cancelled reservation for #{client_phone} at #{slot_time}")
      true
    else
      Rails.logger.warn("[SlotReservationService] Client #{client_phone} tried to cancel slot reserved by #{reserved_by}")
      false
    end
  end

  # Checks if a slot is available (not reserved in Redis).
  #
  # @param slot_time [Time] The appointment slot time
  # @param work_day_id [Integer] The WorkDay ID
  # @return [Boolean] True if available, false if reserved
  def self.slot_available?(slot_time, work_day_id)
    redis_key = build_redis_key(work_day_id, slot_time)
    !REDIS.exists?(redis_key)
  end

  # Checks who has reserved a slot (if anyone).
  #
  # @param slot_time [Time] The appointment slot time
  # @param work_day_id [Integer] The WorkDay ID
  # @return [String, nil] The phone number of the client who reserved it, or nil
  def self.reserved_by(slot_time, work_day_id)
    redis_key = build_redis_key(work_day_id, slot_time)
    REDIS.get(redis_key)
  end

  # Private helper methods

  def self.build_redis_key(work_day_id, slot_time)
    "slot_reservation:#{work_day_id}:#{slot_time.to_i}"
  end
  private_class_method :build_redis_key

  def self.slot_taken_in_db?(slot_time, work_day)
    work_day.appointments
            .where.not(status: "cancelled")
            .where("scheduled_at <= ? AND scheduled_at + (estimated_duration * interval '1 minute') > ?",
                   slot_time, slot_time)
            .exists?
  end
  private_class_method :slot_taken_in_db?
end
