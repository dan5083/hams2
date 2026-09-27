# app/controllers/promises_controller.rb
#
# Routes (config/routes.rb, inside `resources :works_orders`):
#   resources :promises, only: [:create], shallow: true do
#     member { patch :cancel }
#   end
class PromisesController < ApplicationController
  def create
    works_order = WorksOrder.find(params[:works_order_id])
    promise = works_order.promises.build(promise_params)

    if promise.save
      redirect_to works_order_path(works_order, anchor: "promises"),
                  notice: "Promised #{promise.quantity} by #{promise.due_label}."
    else
      redirect_to works_order_path(works_order, anchor: "promises"),
                  alert: promise.errors.full_messages.to_sentence
    end
  end

  def cancel
    promise = Promise.find(params[:id])
    promise.cancel!(Current.user)
    redirect_to works_order_path(promise.works_order, anchor: "promises"),
                notice: "Promise withdrawn."
  end

  private

  def promise_params
    params.require(:promise).permit(:quantity, :due_on, :note)
  end
end
