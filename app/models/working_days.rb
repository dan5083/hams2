# app/models/working_days.rb
#
# Mon-Fri working days, no bank holidays - the same calendar the OTD figures
# on the dashboard use. Kept as one module so a promise "due in 3 wd" and an
# OTD "delivered in 12 wd" can never disagree about what a day is.
module WorkingDays
  module_function

  def working_day?(date)
    date.wday.between?(1, 5)
  end

  # Working days in [start_date, end_date], both ends inclusive. This is the
  # OTD definition (received Monday, released Monday = 1 day).
  def between(start_date, end_date)
    return 0 if start_date.nil? || end_date.nil?
    return 0 if end_date < start_date
    (start_date..end_date).count { |d| working_day?(d) }
  end

  # Signed working days from today to `date`, exclusive of today: due
  # tomorrow = 1, due today = 0, due yesterday = -1. Weekends never count
  # in either direction, so a Friday promise read on Monday is -1, not -3.
  def from_today(date, today: Date.current)
    return 0 if date == today
    if date > today
      ((today + 1)..date).count { |d| working_day?(d) }
    else
      -(date...today).count { |d| working_day?(d) }
    end
  end
end
