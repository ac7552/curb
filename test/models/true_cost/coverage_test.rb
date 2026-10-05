require "test_helper"

class TrueCost::CoverageTest < ActiveSupport::TestCase
  def term(type, years, miles, transferable: true)
    WarrantyTerm.new(country: "US", make_key: "FORD", coverage_type: type, years:, miles:, transferable:)
  end

  test "cover lasts until time or miles run out, whichever is first" do
    # One year old, 12k miles, 12k a year: 3yr/36k has two years left either way.
    inputs = build_inputs(first_used_on: Date.new(2022, 1, 1), as_of: Date.new(2023, 1, 1), mileage: 12_000)
    coverage = TrueCost::Coverage.new(inputs, [ term("bumper_to_bumper", 3, 36_000) ])

    assert_in_delta 2.0, coverage.years_left("bumper_to_bumper"), 0.01
    assert_equal 1.0, coverage.covered("bumper_to_bumper", 1)
    assert_equal 1.0, coverage.covered("bumper_to_bumper", 2).round(2)
    assert_equal 0.0, coverage.covered("bumper_to_bumper", 3)
  end

  test "miles can end cover partway through a year" do
    inputs = build_inputs(first_used_on: Date.new(2022, 1, 1), as_of: Date.new(2023, 1, 1), mileage: 30_000)
    coverage = TrueCost::Coverage.new(inputs, [ term("bumper_to_bumper", 3, 36_000) ])

    assert_in_delta 0.5, coverage.covered("bumper_to_bumper", 1), 0.01
  end

  test "powertrain parts are paid by bumper-to-bumper cover too" do
    inputs = build_inputs(first_used_on: Date.new(2022, 1, 1), as_of: Date.new(2023, 1, 1), mileage: 12_000)
    coverage = TrueCost::Coverage.new(inputs, [ term("bumper_to_bumper", 3, 36_000) ])

    assert_equal 1.0, coverage.covered("powertrain", 1)
    assert_equal 0.0, coverage.covered("corrosion", 1)
    assert_equal 0.0, coverage.covered("none", 1)
  end

  test "terms that don't transfer give a second owner nothing" do
    inputs = build_inputs(first_used_on: Date.new(2022, 1, 1), as_of: Date.new(2023, 1, 1), mileage: 12_000)
    coverage = TrueCost::Coverage.new(inputs, [ term("powertrain", 10, 100_000, transferable: false) ])

    line = coverage.lines.find { |l| l.coverage_type == "powertrain" }
    assert_equal 0.0, line.years_left
    assert_match "second owner", line.note
  end

  test "an extended plan replaces factory cover that has ended" do
    inputs = build_inputs(addon_warranty: "extended", addon_years: 2, addon_miles: nil, addon_coverage: "comprehensive")
    coverage = TrueCost::Coverage.new(inputs, [ term("bumper_to_bumper", 3, 36_000), term("corrosion", 5, nil) ])

    assert_equal 1.0, coverage.covered("bumper_to_bumper", 2)
    assert_equal 0.0, coverage.covered("bumper_to_bumper", 3)
    assert_equal "extended", coverage.lines.find { |l| l.coverage_type == "bumper_to_bumper" }.source
    assert_equal "factory", coverage.lines.find { |l| l.coverage_type == "corrosion" }.source
  end

  test "a powertrain-only plan leaves other parts uncovered" do
    inputs = build_inputs(addon_warranty: "cpo", addon_years: 3, addon_miles: 100_000, addon_coverage: "powertrain")
    coverage = TrueCost::Coverage.new(inputs, [])

    assert_equal 1.0, coverage.covered("powertrain", 3)
    assert_equal 0.0, coverage.covered("bumper_to_bumper", 1)
  end
end
