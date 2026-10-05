require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "signing up signs you in" do
    assert_difference -> { User.count } do
      post registration_path, params: { user: { first_name: " Sam ", last_name: "Rivera", email_address: "New@Example.com",
                                                password: "long-enough", password_confirmation: "long-enough" } }
    end
    assert_redirected_to new_report_path
    assert_equal [ "new@example.com", "Sam Rivera" ], [ User.last.email_address, User.last.name ]
    follow_redirect!
    assert_response :success
  end

  test "sign up shows what to fix" do
    post registration_path, params: { user: { email_address: "one@example.com", password: "short", password_confirmation: "nope" } }

    assert_response :unprocessable_entity
    assert_match "Email address has already been taken", response.body
    assert_match "Password is too short", response.body
  end

  test "signing in with email and password" do
    sign_in_as users(:one)
    assert_redirected_to root_url
    follow_redirect!
    assert_redirected_to reports_path
  end

  test "a wrong password is rejected" do
    sign_in_as users(:one), password: "wrong"
    assert_redirected_to new_session_path
    get reports_path
    assert_redirected_to new_session_path
  end

  test "the landing page is public" do
    get root_path
    assert_response :success
    assert_match "The price is", response.body
  end

  test "the about page is public and linked from the nav, signed in or not" do
    get about_path
    assert_response :success
    assert_select "h1", "Why Curb exists"
    assert_select "nav a[href=?]", about_path

    sign_in_as users(:one)
    get about_path
    assert_response :success
    assert_select "nav .menu__panel a[href=?]", about_path
    assert_select "a[href=?]", new_report_path, text: "Check a car"
  end
end
