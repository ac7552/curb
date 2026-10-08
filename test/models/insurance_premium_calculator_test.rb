require "test_helper"

class InsurancePremiumCalculatorTest < ActiveSupport::TestCase
  # Made-up indexes, not any real model's.
  VEHICLE = { name: "Test car", hldi: { injury: 120, collision: 80, theft: 150 } }.freeze
  DRIVER = { age: 35, accidents: 0, violations: 1, credit_tier: :good, married: true }.freeze

  def calculator(vehicle: VEHICLE, driver: DRIVER, **options)
    Insurance::PremiumCalculator.new(vehicle:, driver:, options:)
  end

  test "prices each coverage from its base rate, the driver, the car's claims index, and the limits or deductible" do
    calc = calculator(deductible: 1000, limits: "100/300/100", discounts: %i[bundle paid_in_full])

    assert_in_delta 1.14, calc.driver_factor, 0.0001, "a violation (×1.20) and married (×0.95)"
    assert_in_delta 450 * 1.14 * 1.20 * 1.45, calc.breakdown[:bodily_injury], 0.01, "injury index 120, 100/300/100 limits"
    assert_in_delta 380 * 1.14 * 0.80 * 1.45, calc.breakdown[:property_damage], 0.01, "collision index stands in for property damage"
    assert_in_delta 210 * 1.14 * 1.50 * 0.85, calc.breakdown[:comprehensive], 0.01, "theft index 150, $1,000 deductible"
    assert_in_delta calc.subtotal * 0.85, calc.total, 0.01, "bundle and paid in full: 15% off"
    assert_in_delta calc.total / 12, calc.monthly, 0.01
  end

  test "uses a property damage index when there is one, and treats a missing index as average" do
    assert_in_delta 0.9, calculator(vehicle: { hldi: { collision: 80, property_damage: 90 } }).vehicle_factor(:property_damage), 0.0001
    assert_equal 1.0, calculator(vehicle: { hldi: {} }).vehicle_factor(:collision)
    assert_not calculator(vehicle: { hldi: {} }).vehicle_known?
  end

  test "caps discounts at 35% and never goes below the minimum premium" do
    every_discount = Insurance::PremiumCalculator::DISCOUNTS.keys
    assert_equal 0.35, calculator(discounts: every_discount).discount_rate

    cheap = calculator(coverages: %i[pip], driver: DRIVER.merge(violations: 0, credit_tier: :excellent))
    assert_equal 400.0, cheap.total
  end

  test "rejects coverages, discounts, deductibles and limits it doesn't know" do
    assert_raises(ArgumentError) { calculator(coverages: %i[rental]) }
    assert_raises(ArgumentError) { calculator(discounts: %i[loyalty]) }
    assert_raises(ArgumentError) { calculator(deductible: 750) }
    assert_raises(ArgumentError) { calculator(limits: "1/2/3") }
    assert_raises(ArgumentError) { calculator(driver: DRIVER.merge(age: 12)).total }
    assert_raises(ArgumentError) { Insurance::PremiumCalculator.new(vehicle: { name: "x" }, driver: DRIVER) }
  end

  test "finds a model's indexes by the model years they cover" do
    InsuranceLossIndex.create!(make_key: "TOYOTA", model_key: "CAMRY", year_from: 2018, year_to: 2022, injury: 110, collision: 95, source: "test")

    assert_equal({ injury: 110, collision: 95 }, InsuranceLossIndex.for(make_key: "TOYOTA", model_key: "CAMRY", model_year: 2020).to_hldi)
    assert_nil InsuranceLossIndex.for(make_key: "TOYOTA", model_key: "CAMRY", model_year: 2017)
  end
end
