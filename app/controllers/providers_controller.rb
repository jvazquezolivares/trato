# frozen_string_literal: true

class ProvidersController < ApplicationController
  layout "public"

  def show
    provider = Provider.includes(:provider_categories, :photos, reviews: :client, :jobs)
                       .find_by!(slug: "#{params[:category_city]}/#{params[:slug]}")
    @profile = ProviderProfileService.call(provider)
  end
end
