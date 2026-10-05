require "test_helper"

class ModelProfilesTest < ActionDispatch::IntegrationTest
  setup do
    Curb::ReferenceData.load!
    sign_in_as users(:one)
  end

  test "looks up any model's profile" do
    get model_profile_path
    assert_response :success
    assert_match "What goes wrong on a car model?", response.body

    get model_profile_path(make: "BMW", model: "3 Series", year: 2014)
    assert_response :success
    assert_match "What goes wrong on the 2014 BMW 3 Series", response.body
    assert_match "Not enough records to tell", response.body
  end
end
