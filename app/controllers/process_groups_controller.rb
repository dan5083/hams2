# app/controllers/process_groups_controller.rb
#
# Grouping lives on the customer order page for now (checkboxes against the
# works orders table + "Batch together"); the record itself is worked on the
# lead WO's existing show page, untouched. Every action lands back where it
# came from via redirect_back.
#
# Routes:
#   resources :process_groups, only: [:create] do
#     member do
#       patch :add_works_order
#       patch :remove_works_order
#       delete :ungroup
#     end
#   end
class ProcessGroupsController < ApplicationController
  before_action :set_process_group, only: [:add_works_order, :remove_works_order, :ungroup]

  # params[:wo_ids] - checkbox ids from the customer order page
  def create
    wos = WorksOrder.where(id: Array(params[:wo_ids]).reject(&:blank?))
    group = ProcessGroup.create_for!(wos)
    redirect_back fallback_location: works_orders_path,
                  notice: "#{group.display_name}: #{group.members.count} works orders batched together " \
                          "(record on WO#{group.lead_works_order.number}, total qty #{group.total_quantity})."
  rescue => e
    redirect_back fallback_location: works_orders_path, alert: e.message
  end

  def add_works_order
    wo = WorksOrder.find(params[:works_order_id])
    @process_group.add_works_order!(wo)
    redirect_back fallback_location: works_order_path(@process_group.lead_works_order),
                  notice: "#{wo.display_name} added to #{@process_group.display_name} " \
                          "(total qty now #{@process_group.total_quantity})."
  rescue => e
    redirect_back fallback_location: works_orders_path, alert: e.message
  end

  # The "push parts over" path: pull a WO out pre-freeze, then batch it into
  # another group (or leave it solo).
  def remove_works_order
    wo = WorksOrder.find(params[:works_order_id])
    @process_group.remove_works_order!(wo)
    redirect_back fallback_location: works_order_path(wo),
                  notice: "#{wo.display_name} removed from the group."
  rescue => e
    redirect_back fallback_location: works_orders_path, alert: e.message
  end

  # Dissolve entirely (pre-freeze only; guard_destroy blocks a frozen group).
  def ungroup
    label = @process_group.display_name
    if @process_group.destroy
      redirect_back fallback_location: works_orders_path, notice: "#{label} dissolved; works orders back to solo records."
    else
      redirect_back fallback_location: works_orders_path, alert: @process_group.errors.full_messages.to_sentence
    end
  end

  private

  def set_process_group
    @process_group = ProcessGroup.find(params[:id])
  end
end
