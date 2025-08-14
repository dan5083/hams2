class ReleaseLevelsController < ApplicationController
  before_action :set_release_level, only: [:edit, :update, :destroy, :toggle_enabled]

  def index
    @release_levels = ReleaseLevel.all.order(:name)
  end

  def new
    @release_level = ReleaseLevel.new
  end

  def create
    @release_level = ReleaseLevel.new(release_level_params)

    if @release_level.save
      redirect_to release_levels_path, notice: 'Release level was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @release_level.update(release_level_params)
      redirect_to release_levels_path, notice: 'Release level was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @release_level.can_be_deleted?
      @release_level.destroy
      redirect_to release_levels_path, notice: 'Release level was successfully deleted.'
    else
      redirect_to release_levels_path, alert: 'Cannot delete release level with associated works orders.'
    end
  end

  def toggle_enabled
    @release_level.update!(enabled: !@release_level.enabled)
    status = @release_level.enabled? ? 'enabled' : 'disabled'
    redirect_to release_levels_path, notice: "Release level was successfully #{status}."
  end

  private

  def set_release_level
    @release_level = ReleaseLevel.find(params[:id])
  end

  def release_level_params
    params.require(:release_level).permit(:name, :statement, :enabled)
  end
end
