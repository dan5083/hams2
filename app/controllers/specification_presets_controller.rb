# app/controllers/specification_presets_controller.rb
class SpecificationPresetsController < ApplicationController
  before_action :set_specification_preset, only: [:show, :edit, :update, :destroy, :toggle_enabled]
  before_action :set_cache_headers

  def index
    @specification_presets = SpecificationPreset.all.order(:name)
  end

  def show
  end

  def new
    @specification_preset = SpecificationPreset.new
  end

  def create
    @specification_preset = SpecificationPreset.new(specification_preset_params)

    if @specification_preset.save
      redirect_to specification_presets_path, notice: 'Specification preset was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @specification_preset.update(specification_preset_params)
      redirect_to specification_presets_path, notice: 'Specification preset was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @specification_preset.can_be_deleted?
      @specification_preset.destroy
      redirect_to specification_presets_path, notice: 'Specification preset was successfully deleted.'
    else
      redirect_to specification_presets_path, alert: 'Cannot delete specification preset that is in use.'
    end
  end

  def toggle_enabled
    @specification_preset.update!(enabled: !@specification_preset.enabled)
    status = @specification_preset.enabled? ? 'enabled' : 'disabled'
    redirect_to specification_presets_path, notice: "Specification preset was successfully #{status}."
  end

  private

  def set_specification_preset
    @specification_preset = SpecificationPreset.find(params[:id])
  end

  def specification_preset_params
    params.require(:specification_preset).permit(:name, :content, :enabled)
  end

  def set_cache_headers
    response.headers['Cache-Control'] = 'no-cache, no-store, max-age=0, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end
end
