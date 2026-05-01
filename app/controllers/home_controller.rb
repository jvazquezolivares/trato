# frozen_string_literal: true

class HomeController < ApplicationController
  layout "public"

  def index
    @homepage = HomepageService.call

    if directory_homepage_enabled?
      render :directory
    else
      render :landing
    end
  end

  private

  def directory_homepage_enabled?
    ENV["FEATURE_DIRECTORY_HOMEPAGE"] == "true"
  end
end
