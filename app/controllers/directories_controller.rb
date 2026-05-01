# frozen_string_literal: true

class DirectoriesController < ApplicationController
  layout "public"

  def show
    @directory = DirectoryService.call(
      category_city: params[:category_city],
      page: params[:page],
      filter: params[:filter]
    )
  end
end
