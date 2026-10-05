require "test_helper"

class ReportTest < ActiveSupport::TestCase
  setup { load_reference_data }

  def build(**attributes)
    users(:one).reports.new({ country: "US", lookup_mode: "model", make: "Ford", model: "Focus", model_year: 2018,
                              odometer: 52_000, asking_price: 9_500, ownership_years: 3, region: "National average",
                              shop_type: "independent", addon_warranty: "none" }.merge(attributes))
  end

  test "stores distances in miles and uses the market default when blank" do
    report = build(country: "NL", region: "Randstad", odometer: 100_000)
    assert report.valid?, report.errors.full_messages.to_sentence

    assert_equal 62_137, report.current_mileage
    assert_equal Market.fetch("NL").default_miles_per_year, report.miles_per_year
    assert_equal 100_000, report.odometer_in_unit
  end

  test "checks VIN format only when looking up by VIN" do
    assert_not build(lookup_mode: "vin", vin: "1FADP3K2XJLOOOOOO").valid?
    assert build(lookup_mode: "vin", vin: "1fadp3k2xjl200000").valid?
    assert build(lookup_mode: "model", vin: "").valid?
  end

  test "requires the terms of an extra warranty plan" do
    report = build(addon_warranty: "extended")
    assert_not report.valid?
    assert report.errors.key?(:addon_years)

    assert build(addon_warranty: "extended", addon_years: 3, addon_coverage: "powertrain").valid?
  end

  test "calculates and stores the four numbers" do
    report = build(emergency_savings: 1_000)
    report.save!
    report.calculate!(as_of: Date.new(2026, 9, 28))

    assert report.calculated?
    assert_equal 3, report.result[:years].size
    assert_operator report.result.dig(:summary, :true_cost), :>=, 9_500
    assert_not report.result.dig(:data, :model_has_data)
    assert_equal "2018 Ford Focus", report.title
  end

  test "only recalls confirmed open on the car zero out a category" do
    report = build(live_data: { recalls: [ { category: "engine" }, { category: "steering", open_on_vehicle: true } ] })

    assert_equal [ DefectCategory.find_by!(slug: "steering").id ], report.recall_category_ids
    assert_equal %w[engine steering], report.model_recall_slugs
  end
end
