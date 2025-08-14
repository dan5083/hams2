class TransportMethodsController < ApplicationController
  before_action :set_transport_method, only: [:edit, :update, :destroy, :toggle_enabled]

  def index
    @transport_methods = TransportMethod.all.order(:name)
  end

  def new
    @transport_method = TransportMethod.new
  end

  def create
    @transport_method = TransportMethod.new(transport_method_params)

    if @transport_method.save
      redirect_to transport_methods_path, notice: 'Transport method was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @transport_method.update(transport_method_params)
      redirect_to transport_methods_path, notice: 'Transport method was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @transport_method.can_be_deleted?
      @transport_method.destroy
      redirect_to transport_methods_path, notice: 'Transport method was successfully deleted.'
    else
      redirect_to transport_methods_path, alert: 'Cannot delete transport method with associated works orders.'
    end
  end

  def toggle_enabled
    @transport_method.update!(enabled: !@transport_method.enabled)
    status = @transport_method.enabled? ? 'enabled' : 'disabled'
    redirect_to transport_methods_path, notice: "Transport method was successfully #{status}."
  end

  private

  def set_transport_method
    @transport_method = TransportMethod.find(params[:id])
  end

  def transport_method_params
    params.require(:transport_method).permit(:name, :description, :enabled)
  end
end
