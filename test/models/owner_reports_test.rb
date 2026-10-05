require "test_helper"

class OwnerReportsTest < ActiveSupport::TestCase
  def counts(make_key, model_key, year, parts)
    parts.each do |slug, complaints|
      ComplaintCount.create!(make_key:, model_key:, model_year: year, category_slug: slug, complaints:,
                             with_miles: complaints, miles_total: complaints * 60_000, towed: complaints / 5)
    end
  end

  setup do
    # Typical cars: engine and electrical dominate, transmission is a small share.
    %w[A B C D].each { |model| counts("ACME", model, 2015, "engine" => 60, "electrical" => 30, "transmission" => 10) }
  end

  test "flags a part that takes far more than its usual share of complaints" do
    counts("FORD", "FOCUS", 2015, "engine" => 60, "electrical" => 30, "transmission" => 110)
    report = OwnerReports.for(make: "Ford", model: "Focus", model_year: 2015)

    assert_equal %w[transmission], report[:flagged]
    transmission = report[:parts].find { |part| part[:slug] == "transmission" }
    assert_equal 60_000, transmission[:average_miles]
    assert_operator transmission[:mix_ratio], :>=, 2
  end

  test "flags a part that is much worse than the model's other years" do
    counts("FORD", "FOCUS", 2013, "transmission" => 12, "engine" => 60)
    counts("FORD", "FOCUS", 2015, "transmission" => 40, "engine" => 200, "electrical" => 90)
    counts("FORD", "FOCUS", 2016, "transmission" => 12, "engine" => 60)

    assert_includes OwnerReports.for(make: "Ford", model: "Focus", model_year: 2015)[:flagged], "transmission"
  end

  test "nothing stands out for a typical car" do
    counts("TOYOTA", "RAV4", 2015, "engine" => 55, "electrical" => 35, "transmission" => 10)
    report = OwnerReports.for(make: "Toyota", model: "RAV4", model_year: 2015)

    assert_equal 100, report[:complaints]
    assert_empty report[:flagged]
  end

  test "adds up trims NHTSA files separately" do
    counts("MERCEDES-BENZ", "C300", 2015, "engine" => 30)
    counts("MERCEDES-BENZ", "C250", 2015, "engine" => 20)
    counts("MERCEDES-BENZ", "CLA250", 2015, "engine" => 99)

    assert_equal 50, OwnerReports.for(make: "Mercedes-Benz", model: "C-Class", model_year: 2015)[:complaints]
  end

  test "points out parts the maker sent an unusual number of fixes for, compared with the same year" do
    counts("LAND ROVER", "DEFENDER", 2015, "engine" => 30)
    20.times do |i|
      ServiceBulletin.create!(document_id: "LR#{i}", make_key: "LAND ROVER", model_key: "DEFENDER", model_year: 2015, title: "Coolant pump", category_slug: "cooling")
    end
    %w[A B C D].each do |model|
      2.times { |i| ServiceBulletin.create!(document_id: "#{model}#{i}", make_key: "ACME", model_key: model, model_year: 2015, title: "Radiator", category_slug: "cooling") }
    end

    bulletins = OwnerReports.for(make: "Land Rover", model: "Defender", model_year: 2015)[:bulletins]

    assert_equal [ "cooling" ], bulletins[:standout]
    assert_equal 1.0, bulletins[:ranks]["cooling"]
  end

  test "counts complaints per car sold, so a popular car isn't punished for being popular" do
    OwnerReports.clear_cache
    (2013..2017).each do |year|
      # a best-seller: lots of complaints, lots of cars
      ComplaintCount.create!(make_key: "HONDA", model_key: "CR-V", model_year: year, category_slug: "engine", complaints: 300)
      ModelSale.create!(make_key: "HONDA", model_key: "CR-V", year:, units: 300_000, source: "test")
      # a minivan: fewer complaints, far fewer cars
      ComplaintCount.create!(make_key: "CHRYSLER", model_key: "PACIFICA", model_year: year, category_slug: "transmission", complaints: 200)
      ModelSale.create!(make_key: "CHRYSLER", model_key: "PACIFICA", year:, units: 100_000, source: "test")
    end

    minivan = OwnerReports.for(make: "Chrysler", model: "Pacifica", model_year: 2015)
    best_seller = OwnerReports.for(make: "Honda", model: "CR-V", model_year: 2015)

    assert_equal 20, minivan.dig(:overall, :per_10k)
    assert_operator minivan.dig(:overall, :ratio), :>, 1.5
    assert_operator best_seller.dig(:overall, :ratio), :<, 1
    assert_includes minivan[:flagged], "transmission"
  end

  test "has no per-car figures without sales" do
    ComplaintCount.create!(make_key: "ACME", model_key: "Z", model_year: 2015, category_slug: "engine", complaints: 50)
    assert_nil OwnerReports.for(make: "Acme", model: "Z", model_year: 2015)[:overall]
  end
end
