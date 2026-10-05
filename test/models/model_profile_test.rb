require "test_helper"

class ModelProfileTest < ActiveSupport::TestCase
  setup do
    Curb::ReferenceData.load!
    @seq = 0
  end

  # count inspections of cars first registered in 2014 and tested at age 8, with part defects
  def inspections(make_key, model_key, count:, parts: {}, engine_key: "2.0-D")
    first_used = Date.new(2014, 3, 1)
    vehicles = Array.new(count) do
      @seq += 1
      { source: "test", external_id: "v#{@seq}", country: "GB", make: make_key, model: model_key, make_key:, model_key:, engine_key:, first_used_on: first_used }
    end
    vehicle_ids = Vehicle.insert_all!(vehicles, returning: :id).rows.flatten
    inspection_ids = Inspection.insert_all!(vehicle_ids.map { |id| { vehicle_id: id, source: "test", external_id: "i#{id}", inspected_on: Date.new(2022, 4, 1), mileage: 80_000, result: "pass" } }, returning: :id).rows.flatten
    parts.each do |slug, (n, kind)|
      category = DefectCategory.find_by!(slug:)
      phrase = DefectPhrase.find_or_create_by!(source: "test", external_id: slug, text: category.name, defect_category: category)
      Defect.insert_all!(inspection_ids.first(n).map { |id| { inspection_id: id, defect_phrase_id: phrase.id, kind: kind || "advisory" } })
    end
  end

  test "flags parts UK inspections record far more often than on other cars the same age" do
    inspections("ACME", "SEDAN", count: 3_000, parts: { "suspension" => [ 300 ], "lights" => [ 300 ] })
    inspections("BMW", "3 SERIES", count: 1_500, parts: { "shock-absorbers" => [ 300 ], "lights" => [ 20 ] })
    DefectRate.refresh_all!(concurrently: false)

    profile = ModelProfile.for(make: "BMW", model: "3 Series", model_year: 2014)
    shocks = profile[:weak_spots].find { |spot| spot[:slug] == "shock-absorbers" }

    assert shocks, "expected shock absorbers to be flagged"
    assert_equal "uk", shocks[:evidence].first[:source]
    assert_operator shocks[:evidence].first[:ratio], :>=, 2
    assert_includes profile[:better].map { |part| part[:slug] }, "lights"
    assert_equal 1_500, profile.dig(:uk, :tests)
  end

  test "a part backed by more than one kind of record ranks first" do
    inspections("ACME", "SEDAN", count: 3_000, parts: { "cooling" => [ 30 ], "shock-absorbers" => [ 60 ] })
    inspections("BMW", "3 SERIES", count: 1_500, parts: { "cooling" => [ 90 ], "shock-absorbers" => [ 150 ] })
    DefectRate.refresh_all!(concurrently: false)
    %w[A B C D E F G H I J].each { |model| 4.times { |i| ServiceBulletin.create!(document_id: "X#{model}#{i}", make_key: "ACME", model_key: model, model_year: 2014, title: "Radio", themes: i.zero? ? %w[water-pump] : []) } }
    5.times { |i| ServiceBulletin.create!(document_id: "B#{i}", make_key: "BMW", model_key: "328I", model_year: 2014, title: "Coolant pump inoperative", themes: %w[water-pump]) }

    spots = ModelProfile.for(make: "BMW", model: "3 Series", model_year: 2014)[:weak_spots]

    assert_equal "cooling", spots.first[:slug]
    assert_equal %w[uk bulletins], spots.first[:evidence].map { |item| item[:source] }
    assert_equal "water-pump", spots.first[:evidence].last[:theme]
  end

  test "says nothing stands out without enough records" do
    inspections("BMW", "3 SERIES", count: 200, parts: { "shock-absorbers" => [ 100 ] })
    DefectRate.refresh_all!(concurrently: false)

    assert_empty ModelProfile.for(make: "BMW", model: "3 Series", model_year: 2014)[:weak_spots]
  end

  test "skips failure themes that can't apply to the car's fuel" do
    assert BulletinTheme.applies?("dpf", "2.0-D")
    assert_not BulletinTheme.applies?("dpf", "2.0-P")
    assert_not BulletinTheme.applies?("charging", "2.0-P")
    assert BulletinTheme.applies?("charging", "EV")
    assert BulletinTheme.applies?("dpf", nil)
  end
end
