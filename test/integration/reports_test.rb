require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  setup do
    Curb::ReferenceData.load!
    sign_in_as users(:one)
    stub_request(:get, %r{commons.wikimedia.org/w/api.php}).to_return(headers: { "Content-Type" => "application/json" }, body: {}.to_json)
  end

  def report_params(**overrides)
    { report: { country: "GB", lookup_mode: "model", make: "Ford", model: "Focus", model_year: 2018, engine: "1.0L",
                fuel_type: "Petrol", odometer: 52_000, asking_price: 7_500, ownership_years: 3, region: "London",
                shop_type: "independent", addon_warranty: "none", emergency_savings: 1_000 }.merge(overrides) }
  end

  test "creating a check shows the true cost" do
    assert_difference -> { Report.count } do
      post reports_path, params: report_params
    end
    report = Report.last
    assert_redirected_to report_path(report)
    follow_redirect!

    assert_response :success
    assert_match "to own it for 3 years", response.body
    assert_match "£", response.body
    assert_select ".reason .reason__headline + .reason__meaning"
    assert_select "details.more", minimum: 4
    assert_select ".sources-list a[href*='data.gov.uk']"
    assert report.calculated?
  end

  test "US checks include NHTSA recalls" do
    stub_request(:get, %r{api.nhtsa.gov/recalls/recallsByVehicle}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { results: [ { NHTSACampaignNumber: "23V905000", Component: "ENGINE AND ENGINE COOLING", Summary: "Oil pump may fail.",
                           Remedy: "Dealers will replace the pump.", ReportReceivedDate: "15/12/2023" } ] }.to_json
    )
    post reports_path, params: report_params(country: "US", region: "National average", emergency_savings: nil)
    follow_redirect!

    assert_match "1 safety recall for this car", response.body
    assert_match "Engine and engine cooling", response.body
    assert_select "a[href='https://www.nhtsa.gov/recalls?nhtsaId=23V905000']"
    assert_select "a.cite[href='https://www.nhtsa.gov/vehicle/2018/FORD/FOCUS']"
    assert_equal "engine", Recall.find_by!(campaign_number: "23V905000").defect_category.slug
  end

  test "US checks say what other owners report" do
    stub_request(:get, %r{api.nhtsa.gov}).to_return(headers: { "Content-Type" => "application/json" }, body: { results: [] }.to_json)
    %w[A B C].each do |model|
      { "engine" => 60, "electrical" => 30, "transmission" => 10 }.each do |slug, complaints|
        ComplaintCount.create!(make_key: "ACME", model_key: model, model_year: 2018, category_slug: slug, complaints:)
      end
    end
    ComplaintCount.create!(make_key: "FORD", model_key: "FOCUS", model_year: 2018, category_slug: "transmission", complaints: 150, with_miles: 150, miles_total: 150 * 62_000)
    ComplaintCount.create!(make_key: "FORD", model_key: "FOCUS", model_year: 2018, category_slug: "engine", complaints: 50)

    post reports_path, params: report_params(country: "US", region: "National average")
    follow_redirect!

    assert_match "What other owners say", response.body
    assert_match "Lots of reports about the transmission and clutch", response.body
    assert_match "62,000 miles", response.body
  end

  test "a lookup failure becomes a note instead of an error" do
    stub_request(:get, %r{api.nhtsa.gov}).to_return(status: 503)
    post reports_path, params: report_params(country: "US", region: "National average")
    follow_redirect!

    assert_response :success
    assert_match "Couldn&#39;t load recalls right now", response.body
  end

  test "invalid input re-renders the form" do
    post reports_path, params: report_params(asking_price: "")
    assert_response :unprocessable_entity
    assert_match "Asking price", response.body
  end

  test "the new-check form starts at the make, with every market's makes" do
    get new_report_path

    assert_response :success
    assert_select "form.wiz[data-report-form-start-value='0']"
    assert_equal Market.codes.sort, JSON.parse(css_select("form.wiz").first["data-report-form-makes-value"]).keys.sort
  end

  test "a form sent back with errors opens on the question that needs fixing" do
    post reports_path, params: report_params(asking_price: "")
    assert_select "form.wiz[data-report-form-start-value='3']"

    post reports_path, params: report_params(model: "")
    assert_select "form.wiz[data-report-form-start-value='2']"
  end

  test "shows checks as cards on a wheel, tagged with their verdict" do
    post reports_path, params: report_params
    get reports_path

    assert_select ".wheel[data-controller='check-wheel'] .check-card[data-kind]", 1
    assert_select ".check-card .check-card__car", "2018 Ford Focus"
    assert_select ".check-card img.make-logo[src*='icons/ford.svg']"
  end

  test "shows a credited photo of a car like this one" do
    stub_request(:get, %r{commons.wikimedia.org/w/api.php}).to_return(headers: { "Content-Type" => "application/json" }, body: {
      query: { pages: { "1" => { index: 1, title: "File:2018 Ford Focus ST-Line, front.jpg", imageinfo: [ {
        mime: "image/jpeg", width: 4000, thumburl: "https://upload.wikimedia.org/focus.jpg", descriptionurl: "https://commons.wikimedia.org/wiki/File:Focus.jpg",
        extmetadata: { LicenseShortName: { value: "CC BY-SA 4.0" }, LicenseUrl: { value: "https://creativecommons.org/licenses/by-sa/4.0" }, Artist: { value: "<a>Vauxford</a>" } }
      } ] } } }
    }.to_json)
    post reports_path, params: report_params
    follow_redirect!

    assert_select ".car-photo img[src='https://upload.wikimedia.org/focus.jpg']"
    assert_select ".car-photo figcaption", /not the one you're looking at.*Vauxford.*CC BY-SA 4.0/m
  end

  test "shows upkeep as shop visits, with the biggest called out" do
    ServiceItem.create!(name: "Oil and filter change", interval_miles: 7_500, interval_months: 12, labor_hours: 0.5, parts_cost_usd: 45)
    ServiceItem.create!(name: "Tires (set of four)", interval_miles: 45_000, labor_hours: 1, parts_cost_usd: 650, wear_item: true)
    post reports_path, params: report_params
    follow_redirect!

    assert_select "#upkeep"
    assert_select "#upkeep-title", /\d+ shop visits? in 3 years/
    assert_select ".visit--big .visit__badge", "Biggest visit"
    assert_select ".visit--big .job-chip", minimum: 1
    assert_select ".rpt-tab[aria-controls=upkeep]", /Upkeep/
  end

  test "an older check fetches its photo once, when opened" do
    post reports_path, params: report_params
    report = Report.last
    report.update!(live_data: report.live_data.except("photo"))

    get report_path(report)
    assert_select "turbo-frame#report_photo[src=?]", photo_report_path(report)

    get photo_report_path(report)
    assert_response :success
    assert report.reload.live_data.key?("photo")
  end

  test "an old check that fails today's rules still gets its photo" do
    post reports_path, params: report_params
    report = Report.last
    report.update_columns(live_data: report.live_data.except("photo"), asking_price: 0)
    assert_not report.valid?

    get photo_report_path(report, card: 1)

    assert_response :success
    assert report.reload.live_data.key?("photo")
  end

  test "checks are private but shareable by link" do
    post reports_path, params: report_params
    report = Report.last

    sign_in_as users(:two)
    get report_path(report)
    assert_response :not_found

    delete session_path
    get shared_report_path(report.share_token)
    assert_response :success
    assert_match "Shared with you", response.body
  end

  test "lists and deletes checks" do
    post reports_path, params: report_params
    get reports_path
    assert_match "2018 Ford Focus", response.body

    assert_difference -> { Report.count }, -1 do
      delete report_path(Report.last)
    end
  end

  test "stops cars that don't exist and suggests real ones" do
    Report.check_cars_exist = true
    Nhtsa::Vpic.models_cache.clear
    stub_request(:get, %r{GetModelsForMakeYear/make/tesla/modelyear/2020}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { Results: %w[Model\ S Model\ X Model\ 3 Model\ Y].map { |name| { Model_Name: name.delete("\\") } } }.to_json
    )

    assert_no_difference -> { Report.count } do
      post reports_path, params: report_params(country: "US", region: "National average", make: "Tesla", model: "Cybertruck", model_year: 2020)
    end
    assert_response :unprocessable_entity
    assert_match "isn&#39;t a 2020 Tesla. Try: Model 3, Model S, Model X, Model Y", response.body
  ensure
    Report.check_cars_exist = false
  end
end
