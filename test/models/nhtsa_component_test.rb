require "test_helper"

class NhtsaComponentTest < ActiveSupport::TestCase
  test "maps NHTSA components to Curb categories" do
    assert_equal "transmission", NhtsaComponent.category_slug("POWER TRAIN:AUTOMATIC TRANSMISSION:TORQUE CONVERTER")
    assert_equal "engine", NhtsaComponent.category_slug("ENGINE AND ENGINE COOLING:ENGINE")
    assert_equal "cooling", NhtsaComponent.category_slug("ENGINE AND ENGINE COOLING:COOLING SYSTEM:RADIATOR ASSEMBLY")
    assert_equal "abs", NhtsaComponent.category_slug("SERVICE BRAKES, HYDRAULIC:ANTILOCK")
    assert_equal "brake-hydraulics", NhtsaComponent.category_slug("SERVICE BRAKES")
    assert_equal "hybrid-battery", NhtsaComponent.category_slug("ELECTRICAL SYSTEM:PROPULSION BATTERY")
    assert_nil NhtsaComponent.category_slug("UNKNOWN OR OTHER")
  end
end
