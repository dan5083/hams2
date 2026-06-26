module DashboardHelper
  # Tailwind colour class for an OTD percentage (nil-safe).
  # green >=90, amber >=75, red below, grey when there's no data.
  def otd_color_class(pct)
    return "text-gray-400" if pct.nil?
    return "text-green-600" if pct >= 90
    return "text-amber-600" if pct >= 75
    "text-red-600"
  end
end
