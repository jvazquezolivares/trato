# frozen_string_literal: true

# Provider panel — authenticated area for managing profile, photos, social media, and assistant config.
# Serves GET /mi-perfil with 4 Turbo Frame tabs.
# All data loading is delegated to ProviderPanelService.
class ProviderPanelController < ApplicationController
  layout "public"

  before_action :require_provider_session
  before_action :load_panel_data, only: :show

  # GET /mi-perfil
  def show; end

  # GET /mi-perfil/tab/:tab_name — Turbo Frame tab content
  def tab
    @provider = current_provider
    @panel = ProviderPanelService.call(@provider)
    tab_name = params[:tab_name]

    unless %w[informacion fotos redes asistente].include?(tab_name)
      head :not_found
      return
    end

    render partial: "provider_panel/tabs/#{tab_name}", locals: { panel: @panel }
  end

  # PATCH /mi-perfil — update basic info
  def update
    @provider = current_provider
    result = update_provider_info

    if result
      redirect_to mi_perfil_path, notice: "Perfil actualizado correctamente."
    else
      load_panel_data
      flash.now[:alert] = "No se pudieron guardar los cambios."
      render :show, status: :unprocessable_entity
    end
  end

  # POST /mi-perfil/photos — upload photos
  def upload_photo
    @provider = current_provider

    unless params[:photo].present?
      redirect_to mi_perfil_path(tab: "fotos"), alert: "Selecciona una foto para subir."
      return
    end

    if @provider.photos.where(profile_photo: false).count >= ProviderPanelService::MAX_PHOTOS
      redirect_to mi_perfil_path(tab: "fotos"), alert: "Has alcanzado el límite de #{ProviderPanelService::MAX_PHOTOS} fotos."
      return
    end

    photo = @provider.photos.create(
      url: "pending_upload",
      profile_photo: false,
      category_tags: []
    )

    photo.file.attach(params[:photo])

    redirect_to mi_perfil_path(tab: "fotos"), notice: "Foto subida correctamente."
  end

  # DELETE /mi-perfil/photos/:id
  def destroy_photo
    @provider = current_provider
    photo = @provider.photos.find_by(id: params[:id])

    if photo
      photo.destroy
      redirect_to mi_perfil_path(tab: "fotos"), notice: "Foto eliminada."
    else
      redirect_to mi_perfil_path(tab: "fotos"), alert: "Foto no encontrada."
    end
  end

  # PATCH /mi-perfil/photos/reorder — reorder photos via drag and drop
  def reorder_photos
    @provider = current_provider
    photo_ids = params[:photo_ids] || []

    photo_ids.each_with_index do |photo_id, index|
      @provider.photos.where(id: photo_id).update_all(position: index)
    end

    head :ok
  end

  private

  def load_panel_data
    @provider = current_provider
    @panel = ProviderPanelService.call(@provider)
  end

  def update_provider_info
    permitted = provider_params
    categories_param = params[:categories]

    ActiveRecord::Base.transaction do
      @provider.update!(permitted)
      update_categories(categories_param) if categories_param.present?
      true
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def provider_params
    params.require(:provider).permit(:name, :city, :service_area, :bio, :base_price, :email)
  end

  def update_categories(categories_param)
    # categories_param is a comma-separated string of category names
    new_names = categories_param.split(",").map(&:strip).reject(&:blank?)
    return if new_names.empty?

    existing = @provider.provider_categories.index_by(&:name)

    # Remove categories not in the new list
    existing.each do |name, category|
      category.destroy unless new_names.include?(name)
    end

    # Add new categories
    new_names.each_with_index do |name, index|
      next if existing[name]

      @provider.provider_categories.create!(
        name: name,
        slug: name.parameterize,
        primary: index.zero? && @provider.provider_categories.none?(&:primary?)
      )
    end
  end
end
