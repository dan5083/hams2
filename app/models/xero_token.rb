# app/models/xero_token.rb
#
# FIX: token refresh must survive the caller's transaction.
#
# AiAssistantJob#run_query evals every tool call inside a transaction — READs
# are rolled back on purpose, WRITEs roll back if anything raises. Before this
# change, XeroToken.current refreshing inside one of those meant the new
# access/refresh pair was written and then thrown away with the rollback,
# while Xero had already rotated the refresh token. The next call then
# re-refreshed with the stale token (only works inside Xero's ~30 min grace
# window) and every subsequent API call 401'd — see the quote-attachment log
# from 07/09: READ create_draft_quote → refresh → rollback → WRITE
# attach_from_request → refresh again → 401 ×5.
#
# The refreshed pair is now persisted on a separate connection (its own
# thread → its own connection → its own transaction), so it commits
# regardless of what the caller does.
class XeroToken < ApplicationRecord
  REFRESH_MUTEX = Mutex.new

  validates :tenant_id, presence: true, uniqueness: true
  validates :access_token, presence: true
  validates :refresh_token, presence: true
  validates :expires_at, presence: true

  # Get the current valid token, refreshing if needed
  def self.current
    token = order(updated_at: :desc).first
    return nil unless token

    token.refresh! if token.expired?
    token
  end

  def expired?
    expires_at < 2.minutes.from_now # refresh with 2 min buffer
  end

  def refresh!
    REFRESH_MUTEX.synchronize do
      # Another thread/tool call may have refreshed while we waited on the
      # mutex. Re-read committed state (visible even inside the caller's
      # transaction under READ COMMITTED) and use it if it's fresh.
      committed = self.class.find(id)
      if !committed.expired?
        adopt(committed.attributes.slice("access_token", "refresh_token", "expires_at", "token_data"))
        return self
      end

      Rails.logger.info "[XeroToken] Refreshing token for #{tenant_name}..."

      uri  = URI("https://identity.xero.com/connect/token")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type:    "refresh_token",
        refresh_token: committed.refresh_token,
        client_id:     ENV["XERO_CLIENT_ID"],
        client_secret: ENV["XERO_CLIENT_SECRET"]
      )

      res = http.request(req)
      raise "Xero token refresh failed (#{res.code}): #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      data  = JSON.parse(res.body)
      attrs = {
        "access_token"  => data["access_token"],
        "refresh_token" => data["refresh_token"],
        "expires_at"    => Time.current + data["expires_in"].to_i.seconds,
        "token_data"    => data,
        "updated_at"    => Time.current
      }

      persist_outside_caller_transaction!(attrs)
      adopt(attrs)

      Rails.logger.info "[XeroToken] Token refreshed successfully"
    end
    self
  rescue => e
    Rails.logger.error "[XeroToken] Refresh failed: #{e.message}"
    raise
  end

  # Store token from OAuth callback
  def self.store_from_callback!(token_set, tenant_id, tenant_name)
    token = find_or_initialize_by(tenant_id: tenant_id)
    token.update!(
      tenant_name:   tenant_name,
      access_token:  token_set["access_token"],
      refresh_token: token_set["refresh_token"],
      expires_at:    Time.current + (token_set["expires_in"] || 1800).to_i.seconds,
      token_data:    token_set
    )
    token
  end

  # Convenience method for API calls
  def bearer_header
    { "Authorization" => "Bearer #{access_token}", "xero-tenant-id" => tenant_id }
  end

  private

  # A new thread checks out its own connection from the pool, so the UPDATE
  # runs in its own (auto-committed) transaction, independent of whatever
  # transaction the caller is inside. update_all bypasses callbacks/validations
  # deliberately — this is a raw persistence step.
  def persist_outside_caller_transaction!(attrs)
    Thread.new do
      self.class.connection_pool.with_connection do
        self.class.where(id: id).update_all(attrs)
      end
    end.join
  end

  def adopt(attrs)
    assign_attributes(attrs)
    clear_changes_information
  end
end
