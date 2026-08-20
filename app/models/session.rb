class Session < ApplicationRecord
  belongs_to :user
  belongs_to :sub_user, optional: true

  # A shop-floor terminal is a shared machine. If Tom walks away mid-job the
  # PIN unlock has to lapse on its own, or the next person signs off in his
  # name without ever touching the keypad.
  SUB_USER_IDLE_TIMEOUT = 20.minutes

  # Cheap write throttle - last_seen only moves once a minute, not once a
  # request.
  SUB_USER_TOUCH_EVERY = 1.minute

  def active_sub_user
    return nil if sub_user_id.blank?
    return nil if sub_user_expired?

    sub_user
  end

  # An unlock only lapses on a clock that has actually run down. A missing
  # timestamp is a gap in the record, not twenty minutes of idleness - it gets
  # repaired by the next touch rather than destroying a live unlock, which
  # otherwise loops: drop the unlock, operator re-keys, drop it again.
  def sub_user_expired?
    return false if sub_user_id.blank?

    seen = sub_user_last_seen_at || sub_user_started_at
    return false if seen.blank?

    seen < SUB_USER_IDLE_TIMEOUT.ago
  end

  def start_sub_user!(record)
    update!(sub_user: record, sub_user_started_at: Time.current, sub_user_last_seen_at: Time.current)
  end

  def end_sub_user!
    update!(sub_user_id: nil, sub_user_started_at: nil, sub_user_last_seen_at: nil)
  end

  def touch_sub_user!
    return if sub_user_id.blank?
    return if sub_user_last_seen_at.present? && sub_user_last_seen_at > SUB_USER_TOUCH_EVERY.ago

    update_column(:sub_user_last_seen_at, Time.current)
  end
end
