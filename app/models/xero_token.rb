# app/models/xero_token.rb
class XeroToken < ApplicationRecord
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
    Rails.logger.info "[XeroToken] Refreshing token for #{tenant_name}..."

    uri = URI("https://identity.xero.com/connect/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.body = URI.encode_www_form(
      grant_type:    "refresh_token",
      refresh_token: refresh_token,
      client_id:     ENV["XERO_CLIENT_ID"],
      client_secret: ENV["XERO_CLIENT_SECRET"]
    )

    res = http.request(req)
    raise "Xero token refresh failed (#{res.code}): #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)

    update!(
      access_token:  data["access_token"],
      refresh_token: data["refresh_token"],
      expires_at:    Time.current + data["expires_in"].to_i.seconds,
      token_data:    data
    )

    Rails.logger.info "[XeroToken] Token refreshed successfully"
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
end
