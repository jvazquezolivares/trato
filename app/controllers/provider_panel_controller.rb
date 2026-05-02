# frozen_string_literal: true

# Provider panel — authenticated area for managing profile, photos, social media, and assistant config.
# Full implementation in task 24. This controller requires an active provider session.
class ProviderPanelController < ApplicationController
  layout "public"

  before_action :require_provider_session

  def show
    @provider = current_provider
  end
end
