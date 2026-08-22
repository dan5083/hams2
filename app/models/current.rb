class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # The operator currently unlocked on this terminal, if any.
  def self.sub_user
    session&.active_sub_user
  end

  # Who a mark on the record belongs to. The sub-user when one is unlocked,
  # otherwise the account holder - unless the account holder is one that may
  # never be named on a record (the kiosk), in which case there is no actor
  # and anything that stamps must demand a PIN unlock first.
  #
  # Permissions still come from Current.user - a PIN unlock adds an identity,
  # it doesn't grant access.
  def self.actor
    candidate = sub_user || user
    candidate if candidate&.can_sign_off?
  end
end
