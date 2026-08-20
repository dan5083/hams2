# NOTE: this is the Rails 8 generated Current plus two class methods. If your
# existing app/models/current.rb has anything else on it, just paste the two
# methods in rather than replacing the file.
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # The operator currently unlocked on this terminal, if any.
  def self.sub_user
    session&.active_sub_user
  end

  # Who a mark on the record belongs to. The sub-user when one is unlocked,
  # otherwise the account holder. Permissions still come from Current.user -
  # a PIN unlock adds an identity, it doesn't grant access.
  def self.actor
    sub_user || user
  end
end
