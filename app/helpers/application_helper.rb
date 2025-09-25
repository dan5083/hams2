module ApplicationHelper
  def operation_signed_off?(works_order, operation)
    works_order.customised_process_data.dig("operations", operation["position"].to_s, "signed_off_at").present?
  end
end
