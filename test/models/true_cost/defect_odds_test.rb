require "test_helper"

class TrueCost::DefectOddsTest < ActiveSupport::TestCase
  include InspectionData

  setup do
    @brakes = DefectCategory.create!(name: "Brakes", slug: "brakes", warranty_type: "bumper_to_bumper")
    # Model X: 30 of 100 cars fail. Model Y: 90 of 900. Average across both: 120 / 1000 = 12%.
    add_inspections(make_key: "ACME", model_key: "X", count: 100, failures: 30, category: @brakes)
    add_inspections(make_key: "ACME", model_key: "Y", count: 900, failures: 90, category: @brakes)
    refresh_rates
  end

  test "pulls a small sample toward the average, adjusted for how this model compares" do
    odds = TrueCost::DefectOdds.new(make_key: "ACME", model_key: "X")
    estimate = odds.estimate(@brakes.id, age: 5, band: 2)

    # r = (30 + 10) / (100 * 0.12 + 10); P = (30 + 50 * 0.12 * r) / (100 + 50)
    ratio = 40.0 / 22
    assert_in_delta ratio, odds.model_ratio(@brakes.id), 0.0001
    assert_in_delta (30 + 50 * 0.12 * ratio) / 150, estimate.probability, 0.0001
    assert_equal 100, estimate.tests
    assert_equal :model, estimate.level
  end

  test "keeps a model's difference from the average at ages it has no records for" do
    # Model N (a new generation) only has records at age 3: twice the average there.
    add_inspections(make_key: "ACME", model_key: "N", count: 400, failures: 96, category: @brakes, age: 3)
    add_inspections(make_key: "ACME", model_key: "Y", count: 400, failures: 48, category: @brakes, age: 3)
    refresh_rates
    odds = TrueCost::DefectOdds.new(make_key: "ACME", model_key: "N", near_age: 3.2)
    at_five = odds.estimate(@brakes.id, age: 5, band: 2)
    average_at_five = TrueCost::DefectOdds.new(make_key: "ACME", model_key: "NONE").estimate(@brakes.id, age: 5, band: 2)

    # 96 failures vs 72 expected (the average includes N itself), smoothed: about 1.29x
    assert_operator odds.model_ratio(@brakes.id), :>, 1.25
    assert_in_delta average_at_five.probability * odds.model_ratio(@brakes.id), at_five.probability, 0.0001
    assert_equal "medium", TrueCost::DefectOdds.confidence_for(at_five.tests)
  end

  test "falls back to the average when the model has no inspections" do
    odds = TrueCost::DefectOdds.new(make_key: "ACME", model_key: "Z")
    estimate = odds.estimate(@brakes.id, age: 5, band: 2)

    assert_in_delta 0.12, estimate.probability, 0.0001
    assert_equal :segment, estimate.level
    assert_not odds.model_has_data?
  end

  test "uses the overall category rate for ages no car has data for" do
    estimate = TrueCost::DefectOdds.new(make_key: "ACME", model_key: "Z").estimate(@brakes.id, age: 15, band: 9)

    assert_in_delta 0.12, estimate.probability, 0.0001
  end

  test "labels confidence by the number of inspections behind a figure" do
    assert_equal "low", TrueCost::DefectOdds.confidence_for(40)
    assert_equal "medium", TrueCost::DefectOdds.confidence_for(100)
    assert_equal "high", TrueCost::DefectOdds.confidence_for(500)
  end
end
