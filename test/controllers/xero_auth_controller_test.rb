require "test_helper"

class XeroAuthControllerTest < ActionDispatch::IntegrationTest
  test "should get authorize" do
    get xero_auth_authorize_url
    assert_response :success
  end

  test "should get callback" do
    get xero_auth_callback_url
    assert_response :success
  end
end
