require "test_helper"

class MakeCatalogTest < ActiveSupport::TestCase
  include InspectionData

  setup do
    load_reference_data
    MakeCatalog.min_make_tests = 3
    MakeCatalog.min_model_tests = 2
    category = DefectCategory.first
    { %w[HONDA JAZZ] => 4, %w[HONDA CIVIC] => 3, %w[HONDA UNCLASSIFIED] => 3, %w[HONDA S2000] => 1,
      %w[VAUXHALL CORSA] => 6, %w[KITCAR SPECIAL] => 1, %w[SMART\ (MCC) FORTWO] => 2, %w[SMART FORFOUR] => 2 }.each do |(make_key, model_key), count|
      add_inspections(make_key:, model_key:, count:, failures: 0, category:)
    end
    refresh_rates
  end

  teardown do
    MakeCatalog.min_make_tests = 5_000
    MakeCatalog.min_model_tests = 300
  end

  test "offers only makes with enough cars, most inspected first" do
    names = MakeCatalog.makes("GB").map { |make| make[:name] }

    assert_equal %w[Honda Vauxhall Smart], names
  end

  test "folds another badge's register name into its make" do
    smart = MakeCatalog.makes("GB").find { |make| make[:name] == "Smart" }

    assert smart, "SMART (MCC) and SMART together pass the threshold"
  end

  test "gives a badge only to makes we have one for" do
    makes = MakeCatalog.makes("GB").to_h { |make| [ make[:name], make[:logo] ] }

    assert_match %r{simple-icons@v13/icons/honda\.svg\z}, makes["Honda"]
    assert_nil MakeCatalog.logo_url("Kitcar")
  end

  test "US makes follow new-car sales" do
    ModelSale.create!(make_key: "VAUXHALL", model_key: "CORSA", year: 2020, units: 10, source: "test")
    ModelSale.create!(make_key: "HONDA", model_key: "CIVIC", year: 2020, units: 500, source: "test")

    assert_equal %w[Honda Vauxhall Smart], MakeCatalog.makes("US").map { |make| make[:name] }
  end

  test "lists a make's own models, most common first, without placeholders" do
    assert_equal %w[Jazz Civic], MakeCatalog.models(make: "Honda", country: "GB")
  end

  test "US models for a year come from NHTSA, the common ones first" do
    ModelSale.create!(make_key: "HONDA", model_key: "CIVIC", year: 2020, units: 500, source: "test")
    stub_request(:get, %r{GetModelsForMakeYear/make/honda/modelyear/2020}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { Results: [ "Accord", "Civic", "Pilot" ].map { |name| { Model_Name: name } } }.to_json
    )
    Nhtsa::Vpic.models_cache.clear

    assert_equal %w[Civic Accord Pilot], MakeCatalog.models(make: "Honda", country: "US", year: "2020")
  end

  test "falls back to its own list when NHTSA is down" do
    stub_request(:get, %r{GetModelsForMakeYear}).to_return(status: 503)
    Nhtsa::Vpic.models_cache.clear

    assert_equal %w[Jazz Civic], MakeCatalog.models(make: "Honda", country: "US", year: "2021")
  end

  test "reads UK Mercedes letters as classes" do
    assert_equal "C-Class", MakeCatalog.display_model("MERCEDES-BENZ", "C")
    assert_equal "A-Class", MakeCatalog.display_model("MERCEDES-BENZ", "A-CLASS")
    assert_equal "GLA", MakeCatalog.display_model("MERCEDES-BENZ", "GLA")
  end
end
