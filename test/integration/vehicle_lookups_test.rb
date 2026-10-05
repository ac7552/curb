require "test_helper"

class VehicleLookupsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "decodes a VIN" do
    stub_request(:get, %r{vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/1FADP3K2XJL200000}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { Results: [ { Make: "FORD", Model: "Focus", ModelYear: "2018", DisplacementL: "2.0", FuelTypePrimary: "Gasoline" } ] }.to_json
    )
    get vehicle_lookup_path(vin: "1FADP3K2XJL200000")

    assert_response :success
    assert_equal({ "make" => "Ford", "model" => "Focus", "model_year" => 2018, "engine" => "2.0L" },
                 response.parsed_body.slice("make", "model", "model_year", "engine"))
  end

  test "lists a make's models for the year, from NHTSA in the US" do
    Nhtsa::Vpic.models_cache.clear
    stub_request(:get, %r{GetModelsForMakeYear/make/tesla/modelyear/2020}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { Results: [ "Model 3", "Model S" ].map { |name| { Model_Name: name } } }.to_json
    )
    get vehicle_models_path(make: "Tesla", year: 2020, country: "US")

    assert_response :success
    assert_equal [ "Model 3", "Model S" ], response.parsed_body
  end

  test "an unknown VIN is a 404 with a message" do
    stub_request(:get, %r{vpic.nhtsa.dot.gov}).to_return(
      headers: { "Content-Type" => "application/json" }, body: { Results: [ { Make: "", Model: "" } ] }.to_json
    )
    get vehicle_lookup_path(vin: "00000000000000000")

    assert_response :not_found
    assert response.parsed_body["error"].present?
  end

  test "looks up Dutch plates at the RDW" do
    stub_request(:get, %r{opendata.rdw.nl/resource/m9d7-ebf2.json}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: [ { merk: "FORD", handelsbenaming: "FOCUS", datum_eerste_toelating: "20200716", cilinderinhoud: "1497" } ].to_json
    )
    stub_request(:get, %r{opendata.rdw.nl/resource/8ys7-d773.json}).to_return(
      headers: { "Content-Type" => "application/json" }, body: [ { brandstof_omschrijving: "Benzine" } ].to_json
    )
    stub_request(:get, %r{opendata.rdw.nl/resource/a34c-vvps.json}).to_return(
      headers: { "Content-Type" => "application/json" }, body: [].to_json
    )
    get vehicle_lookup_path(plate: "k-456-rl", country: "NL")

    assert_response :success
    assert_equal [ "Ford", 2020, "1.5L", "Benzine" ], response.parsed_body.values_at("make", "model_year", "engine", "fuel_type")
    assert_requested :get, %r{kenteken=K456RL}, times: 3
  end

  test "UK plates need the MOT API to be set up" do
    get vehicle_lookup_path(plate: "AB12CDE", country: "GB")

    assert_response :unprocessable_entity
    assert_match "isn't set up", response.parsed_body["error"]
  end
end
