# frozen_string_literal: true

class ProvidersController < ApplicationController
  layout "public"

  def show
    provider = Provider.find_by!(slug: "#{params[:category_city]}/#{params[:slug]}")
    @profile = ProviderProfileService.call(provider)
  end
end
