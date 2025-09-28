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
      # Add the text part (strip any leading whitespace to fix indentation)
      result << h(part.strip) unless part.empty?

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

  # Flash message helpers
  def flash_class(type)
    case type.to_sym
    when :notice
      "bg-green-100 border border-green-400 text-green-700"
    when :alert
      "bg-red-100 border border-red-400 text-red-700"
    when :warning
      "bg-yellow-100 border border-yellow-400 text-yellow-700"
    else
      "bg-blue-100 border border-blue-400 text-blue-700"
    end
  end

  # Currency formatting
  def currency(amount)
    return "£0.00" if amount.nil? || amount == 0
    "£#{number_with_precision(amount, precision: 2)}"
  end

  # Date formatting helpers
  def short_date(date)
    return "" unless date
    date.strftime("%d/%m/%Y")
  end

  def long_date(date)
    return "" unless date
    date.strftime("%d %B %Y")
  end

  def datetime_short(datetime)
    return "" unless datetime
    datetime.strftime("%d/%m/%Y %H:%M")
  end

  # Status badge helpers
  def status_badge(status, custom_classes = nil)
    base_classes = "px-2 py-1 rounded text-xs font-medium"
    status_classes = custom_classes || default_status_classes(status)

    content_tag :span, status.humanize, class: "#{base_classes} #{status_classes}"
  end

  def default_status_classes(status)
    case status.to_s.downcase
    when 'active', 'open', 'enabled'
      'bg-green-100 text-green-800'
    when 'inactive', 'closed', 'disabled', 'voided'
      'bg-red-100 text-red-800'
    when 'processing', 'in_progress'
      'bg-yellow-100 text-yellow-800'
    when 'complete', 'completed'
      'bg-blue-100 text-blue-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  # Navigation helpers
  def active_nav_class(controller_name)
    controller.controller_name == controller_name ? 'bg-blue-700' : ''
  end

  def breadcrumb_link(text, path = nil)
    if path
      link_to text, path, class: "text-blue-600 hover:text-blue-800"
    else
      content_tag :span, text, class: "text-gray-500"
    end
  end

  # Form helpers
  def error_span_for(model, field)
    return unless model.errors[field].any?

    content_tag :span, model.errors[field].first,
                class: "text-red-500 text-xs mt-1 block"
  end

  def required_field_indicator
    content_tag :span, "*", class: "text-red-500"
  end

  # Table helpers
  def sortable_column_header(column, title, current_sort = nil, current_direction = nil)
    direction = current_sort == column && current_direction == 'asc' ? 'desc' : 'asc'

    link_to title, request.params.merge(sort: column, direction: direction),
            class: "text-gray-700 hover:text-gray-900"
  end

  # Pagination info
  def pagination_info(collection)
    return "" unless collection.respond_to?(:current_page)

    start_num = (collection.current_page - 1) * collection.limit_value + 1
    end_num = [collection.current_page * collection.limit_value, collection.total_count].min

    "Showing #{start_num}-#{end_num} of #{collection.total_count} items"
  end

  # Truncate with tooltip
  def truncate_with_tooltip(text, length = 50)
    return "" if text.blank?

    if text.length > length
      content_tag :span, truncate(text, length: length),
                  title: text, class: "cursor-help"
    else
      text
    end
  end

  # Icon helpers (if you're using icons)
  def icon(name, classes = "w-4 h-4")
    # Placeholder for icon implementation
    content_tag :span, "", class: "icon-#{name} #{classes}"
  end

  # Organization/Customer helpers
  def customer_link(customer)
    return "No customer" unless customer

    link_to customer.name, customer, class: "text-blue-600 hover:text-blue-800"
  end

  # Works order helpers
  def works_order_link(works_order)
    return "No WO" unless works_order

    link_to "WO#{works_order.number}", works_order,
            class: "text-blue-600 hover:text-blue-800 font-medium"
  end

  def part_link(part)
    return "No part" unless part

    link_to part.display_name, part, class: "text-blue-600 hover:text-blue-800"
  end

  # Quantity helpers
  def quantity_with_units(quantity, units = "parts")
    return "0 #{units}" unless quantity

    "#{number_with_delimiter(quantity)} #{quantity == 1 ? units.singularize : units}"
  end

  # Progress helpers
  def progress_bar(current, total, classes = "")
    return "" unless total && total > 0

    percentage = (current.to_f / total * 100).round(1)

    content_tag :div, class: "w-full bg-gray-200 rounded-full h-2 #{classes}" do
      content_tag :div, "",
                  class: "bg-blue-600 h-2 rounded-full transition-all duration-300",
                  style: "width: #{percentage}%"
    end
  end

  def progress_text(current, total)
    return "0/0" unless total

    percentage = total > 0 ? (current.to_f / total * 100).round(1) : 0
    "#{current}/#{total} (#{percentage}%)"
  end

  # E-card specific helpers
  def batch_status_badge(status)
    status_badge(status, batch_status_classes(status))
  end

  def batch_status_classes(status)
    case status.to_s.downcase
    when 'active'
      'bg-blue-100 text-blue-800'
    when 'processing'
      'bg-yellow-100 text-yellow-800'
    when 'complete'
      'bg-green-100 text-green-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  # Modal helpers
  def modal_backdrop
    content_tag :div, "",
                class: "fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50",
                data: { action: "click->modal#close" }
  end

  # Loading state helpers
  def loading_spinner(size = "w-4 h-4")
    content_tag :div, "",
                class: "animate-spin rounded-full border-2 border-gray-300 border-t-blue-600 #{size}"
  end

  def skeleton_loader(classes = "h-4 bg-gray-300 rounded")
    content_tag :div, "", class: "animate-pulse #{classes}"
  end
end
