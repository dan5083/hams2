# app/helpers/application_helper.rb
module ApplicationHelper
  # Suggested values for OCV inputs, parsed from the operation's stated ranges.
  # Purely advisory: rendered as a datalist, so operators can always type any
  # value - readings outside the stated range are the ones that matter most.
  def ocv_suggestions(field, operation_text, thickness: nil)
    text = operation_text.to_s
    case field.to_s
    when "temp"
      if (m = text.match(/(\d+)\s*(?:-|to)\s*(\d+)\s*°C/))
        lo, hi = m[1].to_i, m[2].to_i
      elsif (m = text.match(/(\d+)\s*\+\/-\s*(\d+)\s*°C/))
        lo, hi = m[1].to_i - m[2].to_i, m[1].to_i + m[2].to_i
      else
        return []
      end
      numeric_suggestions(lo, hi).map { |v| "#{v}°C" }
    when "time"
      if (plate = plate_time_suggestions(text, thickness))
        plate
      elsif (m = text.match(/(\d+)\s*(?:-|to)\s*(\d+)\s*sec/i))
        unit_suggestions(m[1].to_i, m[2].to_i, "secs")
      elsif (m = text.match(/(\d+)\s*sec/i))
        ["#{m[1]} secs"]
      elsif (m = text.match(/(\d+)\s*(?:-|to)\s*(\d+)\s*min/i))
        unit_suggestions(m[1].to_i, m[2].to_i, "mins")
      elsif (m = text.match(/(\d+)\s*min/i))
        ["#{m[1]} mins"]
      elsif (m = text.match(/(\d+)\s*(?:-|to)\s*(\d+)\s*hour/i))
        hour_suggestions(m[1].to_i, m[2].to_i)
      elsif (m = text.match(/(\d+)\s*hour/i))
        hour_suggestions(m[1].to_i, m[1].to_i)
      else
        []
      end
    when "volts"
      if (m = text.match(/(\d+)\s*(?:-|to)\s*(\d+)\s*V\b/))
        numeric_suggestions(m[1].to_i, m[2].to_i).map { |v| "#{v} V" }
      else
        []
      end
    else
      []
    end
  end

  # ENP plate ops state a deposition rate, not a duration; combined with the
  # operation's numeric target thickness the plate time is derivable. No prose
  # parsing: a part set up without a target thickness gets no suggestion.
  def plate_time_suggestions(text, thickness)
    rate = text.match(/Deposition rate:?\s*(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*(?:μ|u)m\/hour/i)
    t = thickness.to_f
    return nil unless rate && t > 0

    r_lo, r_hi = rate[1].to_f, rate[2].to_f
    return nil if r_lo <= 0

    mins_lo = ((t * 60 / r_hi) / 5.0).floor * 5
    mins_hi = ((t * 60 / r_lo) / 5.0).ceil * 5
    return nil if mins_hi <= 0 || mins_hi > 24 * 60

    step = [5, (((mins_hi - mins_lo) / 11.0) / 5.0).ceil * 5].max
    vals = (mins_lo..mins_hi).step(step).to_a
    vals << mins_hi unless vals.last == mins_hi
    vals.map { |v| "#{v} mins" }
  end

  def numeric_suggestions(lo, hi)
    return [] if hi < lo
    step = [1, ((hi - lo) / 11.0).ceil].max
    vals = (lo..hi).step(step).to_a
    vals << hi unless vals.last == hi
    vals.map(&:to_s)
  end

  def unit_suggestions(lo, hi, unit)
    numeric_suggestions(lo, hi).map { |v| "#{v} #{unit}" }
  end

  def hour_suggestions(lo, hi)
    out = []
    (lo..hi).each do |h|
      out << "#{h} h"
      out << "#{h} h 30 m" if h < hi || lo == hi
    end
    out.first(12)
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
