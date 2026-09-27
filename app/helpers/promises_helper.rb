# app/helpers/promises_helper.rb
module PromisesHelper
  PROMISE_PILL_CLASSES = {
    overdue: "bg-red-600 text-white",
    urgent:  "bg-amber-400 text-amber-950",
    ok:      "bg-emerald-100 text-emerald-800",
    met:     "bg-gray-100 text-gray-500 line-through",
  }.freeze

  # The promise pill: "🤝 50 by Thu 2 Oct · 3 wd". compact: drops the
  # quantity/date for tight cells - "🤝 3 wd" - with the full text in the
  # title. Renders nothing for nil so callers can pass job.promise blind.
  def promise_pill(promise, compact: false)
    return if promise.nil?
    full = "#{promise.quantity} by #{promise.due_label} · #{promise.countdown_label}"
    full += " — #{promise.note}" if promise.note.present?
    text = compact ? promise.countdown_label : "#{promise.quantity} by #{promise.due_label} · #{promise.countdown_label}"
    content_tag :span, "🤝 #{text}",
      class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-bold whitespace-nowrap #{PROMISE_PILL_CLASSES[promise.status]}",
      title: full
  end

  # Row highlight for boards: promised work is tinted so it reads at a
  # glance even before the pill is spotted.
  def promise_row_class(promise)
    return "" if promise.nil?
    case promise.status
    when :overdue then "bg-red-50"
    when :urgent  then "bg-amber-50"
    else "bg-emerald-50/60"
    end
  end
end
