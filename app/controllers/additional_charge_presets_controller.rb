# app/controllers/additional_charge_presets_controller.rb
class AdditionalChargePresetsController < ApplicationController
  before_action :set_additional_charge_preset, only: [:show, :edit, :update, :destroy, :toggle_enabled]

  def index
    @additional_charge_presets = AdditionalChargePreset.all.order(:name)
  end

  def show
  end

  def new
    @additional_charge_preset = AdditionalChargePreset.new
  end

  def create
    @additional_charge_preset = AdditionalChargePreset.new(additional_charge_preset_params)

    if @additional_charge_preset.save
      redirect_to additional_charge_presets_path, notice: 'Additional charge preset was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @additional_charge_preset.update(additional_charge_preset_params)
      redirect_to additional_charge_presets_path, notice: 'Additional charge preset was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @additional_charge_preset.can_be_deleted?
      @additional_charge_preset.destroy
      redirect_to additional_charge_presets_path, notice: 'Additional charge preset was successfully deleted.'
    else
      redirect_to additional_charge_presets_path, alert: 'Cannot delete charge preset that is in use.'
    end
  end

  def toggle_enabled
    @additional_charge_preset.update!(enabled: !@additional_charge_preset.enabled)
    status = @additional_charge_preset.enabled? ? 'enabled' : 'disabled'
    redirect_to additional_charge_presets_path, notice: "Additional charge preset was successfully #{status}."
  end

  private

  def set_additional_charge_preset
    @additional_charge_preset = AdditionalChargePreset.find(params[:id])
  end

  def additional_charge_preset_params
    params.require(:additional_charge_preset).permit(:name, :description, :amount, :is_variable, :calculation_type, :enabled)
  end
end
