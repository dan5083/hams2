require "test_helper"

class TransportMethodsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get transport_methods_index_url
    assert_response :success
  end

  test "should get new" do
    get transport_methods_new_url
    assert_response :success
  end

  test "should get create" do
    get transport_methods_create_url
    assert_response :success
  end

  test "should get edit" do
    get transport_methods_edit_url
    assert_response :success
  end

  test "should get update" do
    get transport_methods_update_url
    assert_response :success
  end

  test "should get destroy" do
    get transport_methods_destroy_url
    assert_response :success
  end

  test "should get toggle_enabled" do
    get transport_methods_toggle_enabled_url
    assert_response :success
  end
end
