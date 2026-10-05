require "test_helper"

class TrueCost::MaintenancePlanTest < ActiveSupport::TestCase
  def item(name, miles: nil, months: nil, labor_hours: 0.5, parts: 45)
    ServiceItem.new(name:, interval_miles: miles, interval_months: months, labor_hours:, parts_cost_usd: parts)
  end

  test "counts services due in each year of ownership" do
    inputs = build_inputs(mileage: 0, first_used_on: Date.new(2023, 1, 1), as_of: Date.new(2023, 1, 1), miles_per_year: 7_500)
    plan = TrueCost::MaintenancePlan.new(inputs, [ item("Oil", miles: 7_500, months: 12) ])

    assert_equal [ 1, 1, 1 ], plan.by_year.map { |services| services.sum(&:count) }
    assert_equal 95, plan.cost_in_year(1) # 0.5h at 100 + 45 in parts
  end

  test "whichever interval comes first sets the schedule" do
    # 15k miles a year hits a 7,500-mile interval twice a year before 12 months pass.
    inputs = build_inputs(mileage: 0, first_used_on: Date.new(2023, 1, 1), as_of: Date.new(2023, 1, 1), miles_per_year: 15_000)
    plan = TrueCost::MaintenancePlan.new(inputs, [ item("Oil", miles: 7_500, months: 12) ])

    assert_equal 2, plan.by_year.first.first.count
  end

  test "time-only items follow the car's age" do
    # 18 months old with a 24-month interval: due in 6 months, then every 2 years.
    inputs = build_inputs(first_used_on: Date.new(2021, 7, 1), as_of: Date.new(2023, 1, 1), years: 3)
    plan = TrueCost::MaintenancePlan.new(inputs, [ item("Brake fluid", months: 24) ])

    assert_equal [ 1, 0, 1 ], plan.by_year.map { |services| services.sum(&:count) }
  end

  test "skips services that won't come due" do
    inputs = build_inputs(mileage: 10_000, miles_per_year: 10_000, years: 3)
    plan = TrueCost::MaintenancePlan.new(inputs, [ item("Spark plugs", miles: 100_000) ])

    assert plan.by_year.all?(&:empty?)
  end

  test "groups services into shop visits paced by the oil change" do
    # Nearly 3 years old, so the 3-year battery and the yearly wipers are due in about 2 months.
    inputs = build_inputs(mileage: 0, first_used_on: Date.new(2020, 3, 1), as_of: Date.new(2023, 1, 1), miles_per_year: 10_000, years: 3)
    wear = ->(name, months) { item(name, months:).tap { _1.wear_item = true } }
    plan = TrueCost::MaintenancePlan.new(inputs, [ item("Oil", miles: 10_000), item("Cabin filter", miles: 20_000), wear.("Battery", 36), wear.("Wipers", 12) ])

    visits = plan.visits

    assert_equal [ 2, 12, 24, 36 ], visits.map { (_1.at * 12).round }
    assert_equal %w[Battery Wipers], visits.first.items.map(&:name).sort, "too far from an oil change, so a visit of their own"
    assert_equal [ "Cabin filter", "Oil", "Wipers" ], visits.third.items.map(&:name).sort
    assert_equal plan.by_year.flatten.sum(&:count), visits.sum { _1.items.size }
  end
end
