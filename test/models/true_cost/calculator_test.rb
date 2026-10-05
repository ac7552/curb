require "test_helper"

class TrueCost::CalculatorTest < ActiveSupport::TestCase
  # Every category has the same chance every year.
  class FlatOdds
    def initialize(probability) = @probability = probability
    def estimate(*, **) = TrueCost::DefectOdds::Estimate.new(probability: @probability, tests: 600, failures: 0, level: :model)
    def model_tests = 5_000
    def model_has_data? = true
  end

  setup do
    @engine = DefectCategory.new(id: 1, name: "Engine", slug: "engine", warranty_type: "powertrain", labor_hours: 0, parts_cost_usd: 1_000)
    @tires = DefectCategory.new(id: 2, name: "Tires", slug: "tyres", warranty_type: "none", wear_item: true, labor_hours: 0, parts_cost_usd: 600)
  end

  def calculate(inputs, terms: [], odds: FlatOdds.new(0.1))
    TrueCost::Calculator.new(inputs, categories: [ @engine, @tires ], terms:, schedule: [], odds:, typical_odds: FlatOdds.new(0.2)).call
  end

  test "true cost is price plus expected repairs plus maintenance" do
    result = calculate(build_inputs(years: 2))

    assert_equal [ 100, 100 ], result[:years].map { |year| year[:repairs] }
    assert_equal 200, result[:summary][:repairs]
    assert_equal 10_200, result[:summary][:true_cost]
  end

  test "compares repairs with an average car of the same age and miles" do
    result = calculate(build_inputs(years: 2))

    assert_equal 200, result[:summary][:repairs]
    assert_equal 400, result[:summary][:typical_repairs]
  end

  test "wear items are left to maintenance, never priced as problems" do
    result = calculate(build_inputs)

    assert_equal [ "engine" ], result[:problems].map { |problem| problem[:slug] }
  end

  test "warranty takes covered years off the bill" do
    # 1.5 years of powertrain left: year 1 is free, year 2 is half covered.
    term = WarrantyTerm.new(coverage_type: "powertrain", years: 4, miles: nil, transferable: true)
    inputs = build_inputs(years: 2, first_used_on: Date.new(2020, 7, 2), as_of: Date.new(2023, 1, 1))
    result = calculate(inputs, terms: [ term ])

    assert_equal [ 0, 50 ], result[:years].map { |year| year[:repairs] }
    assert_equal 150, result[:summary][:warranty_saves]
  end

  test "a recall confirmed open on the car means the buyer pays nothing for that part" do
    result = calculate(build_inputs(recall_category_ids: [ @engine.id ]))

    assert_equal 0, result[:summary][:repairs]
    assert result[:problems].first[:recall]
  end

  test "break-the-bank risk counts only repairs bigger than savings" do
    result = calculate(build_inputs(years: 2, emergency_savings: 500.0))

    assert_equal [ 0.1, 0.1 ], result[:years].map { |year| year[:break_bank] }
    assert_in_delta 0.19, result[:summary][:break_bank_any], 0.0001

    assert_equal 0.0, calculate(build_inputs(emergency_savings: 5_000.0))[:summary][:break_bank_any]
    assert_nil calculate(build_inputs)[:summary][:break_bank_any]
  end

  test "budget check compares the costliest year to the monthly budget" do
    assert calculate(build_inputs(monthly_budget: 10.0))[:budget][:fits]
    assert_not calculate(build_inputs(monthly_budget: 5.0))[:budget][:fits]
    assert_nil calculate(build_inputs)[:budget]
  end

  test "flags US results as a proxy for European data" do
    assert calculate(build_inputs)[:data][:proxy]
    assert_not calculate(build_inputs(market: Market.fetch("GB")))[:data][:proxy]
  end

  test "uses the maker's guide for the exact car when it has been checked" do
    ServiceItem.create!(name: "Oil and filter change", interval_miles: 7_500, interval_months: 12, labor_hours: 0.5, parts_cost_usd: 45)
    ServiceItem.create!(name: "Spark plugs", interval_miles: 100_000, labor_hours: 1, parts_cost_usd: 80)
    ServiceItem.create!(name: "Wiper blades", interval_months: 12, labor_hours: 0.1, parts_cost_usd: 35)
    row = ->(name, miles, months, applies_to = nil) { { "name" => name, "interval_miles" => miles, "interval_months" => months, "applies_to" => applies_to, "source_page" => 39 } }
    guide = MaintenanceGuide.create!(make_key: "TOYOTA", model_key: "TACOMA", model_year: 2019, make: "Toyota", model: "Tacoma", status: "ok",
                                     url: "https://example.test/guide.pdf", title: "Toyota 2019 Tacoma Warranty & Maintenance Guide",
                                     rows: [ row.("Oil and filter change", 10_000, 12), row.("Spark plugs", 120_000, nil, "2TR-FE engine only"),
                                             row.("Spark plugs", 60_000, 72, "2GR-FKS engine only") ])
    inputs = build_inputs(make_key: "TOYOTA", model_key: "TACOMA", model_year: 2019)
    calculate = -> { TrueCost::Calculator.new(inputs, categories: [ @engine ], terms: [], odds: FlatOdds.new(0.1), typical_odds: FlatOdds.new(0.1)).call }

    result = calculate.call
    services = result[:maintenance].first[:services].index_by { _1[:name] }

    assert_equal 1, services["Oil and filter change"][:count], "every 10,000 miles at 12,000 a year"
    assert_equal({ title: guide.title, url: guide.url, items: { "Oil and filter change" => [ 39 ], "Spark plugs" => [ 39 ] } }, result[:schedule_source])
    assert_equal [ [ "Oil and filter change", 10_000, [ 39 ] ], [ "Spark plugs", 60_000, [ 39 ] ], [ "Wiper blades", nil, nil ] ],
                 result[:schedule].map { _1.values_at(:name, :interval_miles, :guide_pages) }
    assert_equal 60_000, guide.apply_to(ServiceItem.all.to_a).find { _1.name == "Spark plugs" }.interval_miles, "engine unknown, so the more frequent"
    assert_equal 7_500, ServiceItem.find_by!(name: "Oil and filter change").interval_miles, "the usual schedule is left alone"

    guide.update!(status: "needs_review")
    assert_nil calculate.call[:schedule_source]
  end

  test "an electric car isn't charged for oil, spark plugs or other engine work" do
    ServiceItem.create!(name: "Oil and filter change", interval_miles: 7_500, interval_months: 12, labor_hours: 0.5, parts_cost_usd: 45)
    ServiceItem.create!(name: "Spark plugs", interval_miles: 30_000, labor_hours: 1, parts_cost_usd: 80)
    ServiceItem.create!(name: "Cabin air filter", interval_miles: 15_000, interval_months: 24, labor_hours: 0.2, parts_cost_usd: 25)
    run = ->(inputs) { TrueCost::Calculator.new(inputs, categories: [ @engine ], terms: [], odds: FlatOdds.new(0.1), typical_odds: FlatOdds.new(0.1)).call[:schedule].map { _1[:name] } }

    assert_equal [ "Cabin air filter" ], run.(build_inputs(make_key: "TESLA", model_key: "MODEL 3"))
    assert_equal [ "Cabin air filter" ], run.(build_inputs(make_key: "FORD", model_key: "MUSTANG MACH-E", engine_key: "EV"))
    assert_includes run.(build_inputs), "Oil and filter change"
  end
end
