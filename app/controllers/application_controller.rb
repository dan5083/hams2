class ApplicationController < ActionController::Base
  include Authentication

  # Prevent caching of authenticated pages to avoid stale dropdown data
  before_action :set_cache_headers

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def set_cache_headers
    # Prevent browser and proxy caching of dynamic content
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end
end
