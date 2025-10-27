# app/controllers/buyers_controller.rb
class BuyersController < ApplicationController
  before_action :set_organization
  before_action :set_buyer, only: [:edit, :update, :destroy, :toggle_enabled]

  def index
    @buyers = @organization.buyers.order(:email)
  end

  def new
    @buyer = @organization.buyers.new
  end

  def create
    @buyer = @organization.buyers.new(buyer_params)

    if @buyer.save
      redirect_to organization_buyers_path(@organization),
                  notice: 'Buyer was successfully added.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @buyer.update(buyer_params)
      redirect_to organization_buyers_path(@organization),
                  notice: 'Buyer was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @buyer.destroy
    redirect_to organization_buyers_path(@organization),
                notice: 'Buyer was successfully removed.'
  end

  def toggle_enabled
    @buyer.update(enabled: !@buyer.enabled)

    respond_to do |format|
      format.html do
        redirect_to organization_buyers_path(@organization),
                    notice: "Buyer was successfully #{@buyer.enabled? ? 'enabled' : 'disabled'}."
      end
      format.turbo_stream
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_buyer
    @buyer = @organization.buyers.find(params[:id])
  end

  def buyer_params
    params.require(:buyer).permit(:email, :enabled)
  end
end
