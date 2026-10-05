require "test_helper"

class VehicleNameTest < ActiveSupport::TestCase
  test "make keys are upper case with aliases merged" do
    assert_equal "VOLKSWAGEN", VehicleName.make_key(" Volkswagen ")
    assert_equal "VOLKSWAGEN", VehicleName.make_key("vw")
    assert_equal "MERCEDES-BENZ", VehicleName.make_key("Mercedes Benz")
  end

  test "model keys keep the family name only" do
    assert_equal "GOLF", VehicleName.model_key("Golf GTI")
    assert_equal "CIVIC", VehicleName.model_key("civic  type r")
    assert_equal "CR-V", VehicleName.model_key("CR-V")
    assert_equal "3 SERIES", VehicleName.model_key("3 Series 320d")
  end

  test "keeps names shared by different cars apart" do
    assert_equal "GRAND CHEROKEE", VehicleName.model_key("Grand Cherokee L")
    assert_equal "MODEL Y", VehicleName.model_key("Model Y")
    assert_equal "TRANSIT CONNECT", VehicleName.model_key("Transit Connect")
    assert_equal "TRANSIT", VehicleName.model_key("Transit 350 HD")
    assert_equal "RANGE ROVER EVOQUE", VehicleName.model_key("Range Rover Evoque")
    assert_equal "RANGE ROVER", VehicleName.model_key("Range Rover Vogue")
    assert_equal "TOWN & COUNTRY", VehicleName.model_key("Town & Country")
    assert_equal "COROLLA", VehicleName.model_key("Corolla Icon")
  end

  test "display names read like the badge on the car" do
    assert_equal "BMW X1", VehicleName.display(make: "BMW", model: "X1")
    assert_equal "Ford Focus", VehicleName.display(make: "FORD", model: "FOCUS")
    assert_equal "Honda CR-V", VehicleName.display(make: "honda", model: "CR-V")
    assert_equal "Toyota RAV4", VehicleName.display(make: "TOYOTA", model: "RAV4")
  end

  test "offers the UK register's spelling of US model names" do
    assert_equal [ "C-CLASS", "C" ], VehicleName.model_key_candidates("Mercedes-Benz", "C-Class")
    assert_includes VehicleName.model_key_candidates("Mazda", "Mazda3"), "3"
    assert_equal "RANGE ROVER EVOQUE", VehicleName.model_key_candidates("Land Rover", "Range Rover Evoque").first
    assert_equal [ "CIVIC", "CIVIC TYPE" ], VehicleName.model_key_candidates("Honda", "Civic Type R")
    assert_includes VehicleName.model_key_candidates("BMW", "330i"), "3 SERIES"
    assert_includes VehicleName.model_key_candidates("Mercedes-Benz", "C300"), "C"
  end

  test "groups trims NHTSA files separately into one family" do
    assert_match Regexp.new(VehicleName.trim_family_pattern("Mercedes-Benz", "C-Class")), "C300"
    assert_no_match Regexp.new(VehicleName.trim_family_pattern("Mercedes-Benz", "C-Class")), "CLA250"
    assert_match Regexp.new(VehicleName.trim_family_pattern("BMW", "330i")), "328XI"
    assert_nil VehicleName.trim_family_pattern("Ford", "Focus")
  end

  test "engine keys combine liters and fuel" do
    assert_equal "1.6-P", VehicleName.engine_key(cc: 1598, fuel: "PE")
    assert_equal "2.0-P", VehicleName.engine_key(liters: 1.998, fuel: "Gasoline")
    assert_equal "1.5-P", VehicleName.engine_key(liters: 1.5, fuel: "Benzine")
    assert_equal "1.8-H", VehicleName.engine_key(cc: 1798, fuel: "Hybrid Electric")
    assert_equal "EV", VehicleName.engine_key(fuel: "Electric")
    assert_equal "2.2", VehicleName.engine_key(cc: 2199)
    assert_nil VehicleName.engine_key(fuel: "Diesel")
  end
end
