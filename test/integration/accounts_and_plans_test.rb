require "test_helper"

class AccountsAndPlansTest < ActionDispatch::IntegrationTest
  setup do
    Curb::ReferenceData.load!
    stub_request(:get, %r{commons.wikimedia.org/w/api.php}).to_return(headers: { "Content-Type" => "application/json" }, body: {}.to_json)
  end

  def check_params
    { report: { country: "GB", lookup_mode: "model", make: "Ford", model: "Focus", model_year: 2018, engine: "1.0L", fuel_type: "Petrol",
                odometer: 52_000, asking_price: 7_500, ownership_years: 3, region: "London", shop_type: "independent", addon_warranty: "none" } }
  end

  test "sign-up needs a first and last name" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { user: { first_name: "", last_name: "", email_address: "a@example.com", password: "long-enough", password_confirmation: "long-enough" } }
    end
    assert_response :unprocessable_entity
  end

  test "saves your details, and new checks start from where you live" do
    sign_in_as users(:one)

    patch account_path, params: { user: { first_name: "Sam", last_name: "Rivera", country: "GB", postal_code: "sw1a 1aa", car_types: [ "", "suv", "sport" ] } }
    assert_redirected_to account_path

    user = users(:one).reload
    assert_equal [ "Sam Rivera", "GB", "SW1A 1AA", %w[suv sport], "London" ], [ user.name, user.country, user.postal_code, user.car_types, user.region ]

    get new_report_path
    assert_select "select[name='report[country]'] option[selected][value='GB']"
    assert_select "select[name='report[region]'] option[selected][value='London']"
  end

  test "the account page asks for names an older account never gave" do
    sign_in_as users(:one)

    patch account_path, params: { user: { first_name: "", last_name: "", car_types: [ "" ] } }

    assert_response :unprocessable_entity
    assert_select ".errors", /First name/
  end

  test "Free allows three checks a month; Plus has no limit" do
    with_billing do
      user = users(:one)
      sign_in_as user
      3.times { user.record_use!(:check) }

      assert_no_difference -> { Report.count } do
        post reports_path, params: check_params
      end
      assert_redirected_to plans_path
      assert_match "used your 3 free checks", flash[:alert]

      user.update!(plan: "plus")
      assert_difference -> { user.usage_events.where(kind: "check").count } do
        post reports_path, params: check_params
      end
      assert_redirected_to report_path(Report.last)
    end
  end

  test "last month's checks don't count against this month" do
    with_billing do
      user = users(:one)
      travel_to 1.month.ago { 3.times { user.record_use!(:check) } }

      assert_equal 3, user.remaining(:check)
    end
  end

  test "the plans page shows both plans, and says when payments aren't switched on" do
    with_billing do
      get plans_path
      assert_select ".plan", 2
      assert_select ".plan__price", /\$1\.99/

      sign_in_as users(:one)
      post subscription_path(plan: "plus", interval: "month")
      assert_redirected_to plans_path
      assert_match "aren't switched on", flash[:alert]
    end
  end

  test "with billing switched off, there are no plans, payments or limits" do
    user = users(:one)
    sign_in_as user
    5.times { user.record_use!(:check) }

    assert_difference -> { Report.count } do
      post reports_path, params: check_params
    end
    assert_redirected_to report_path(Report.last)

    get plans_path
    assert_response :not_found
    post subscription_path(plan: "plus", interval: "month")
    assert_response :not_found

    get account_path
    assert_select "#plan-heading", count: 0
    assert_select "a[href=?]", plans_path, count: 0
    get new_report_path
    assert_select ".checks-left", count: 0
  end
end
