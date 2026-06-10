# frozen_string_literal: true

# Public privacy policy page required by Meta for WhatsApp Business approval.
# Accessible without authentication at /privacy
class PrivacyController < ApplicationController
  skip_before_action :verify_authenticity_token
  layout "application"

  def show
    # Public page, no authentication required
  end
end
