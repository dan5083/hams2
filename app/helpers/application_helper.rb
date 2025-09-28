# app/helpers/application_helper.rb
module ApplicationHelper
  def operation_signed_off?(works_order, operation)
    works_order.customised_process_data.dig("operations", operation["position"].to_s, "signed_off_at").present?
  end

  def batch_operation_signed_off?(works_order, operation_position, batch_id)
    works_order.customised_process_data.dig("batch_operations", batch_id.to_s, operation_position.to_s, "signed_off_at").present?
  end

  def render_operation_text_with_inputs(text, works_order, operation_position)
    return text unless text.include?('_')

    parts = text.split('_')
    result = []

    parts.each_with_index do |part, index|
      # Add the text part
      result << h(part) unless part.empty?

      # Add input field between parts (except after the last part)
      if index < parts.length - 1
        input_id = "op_#{operation_position}_input_#{index}"
        saved_value = works_order.customised_process_data.dig("operation_inputs", operation_position.to_s, index.to_s) || ""

        result << content_tag(:input, nil,
          type: "text",
          id: input_id,
          name: "operation_inputs[#{operation_position}][#{index}]",
          value: saved_value,
          class: "inline-block w-20 px-1 py-0 text-xs border border-gray-300 rounded mx-1 focus:outline-none focus:ring-1 focus:ring-blue-500",
          placeholder: "___",
          data: {
            "operation-text-inputs-target": "input",
            "input-index": index,
            action: "blur->operation-text-inputs#saveInput keydown->operation-text-inputs#handleKeyDown"
          }
        )
      end
    end

    result.join.html_safe
  end
end
