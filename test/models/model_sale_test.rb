require "test_helper"

class ModelSaleTest < ActiveSupport::TestCase
  test "adds up cars sold only when every year is known" do
    [ 2020, 2021 ].each { |year| ModelSale.create!(make_key: "TOYOTA", model_key: "SIENNA", year:, units: 50_000, source: "test") }

    assert_equal 100_000, ModelSale.units_for(make_key: "TOYOTA", model_key: "SIENNA", years: 2020..2021)
    assert_nil ModelSale.units_for(make_key: "TOYOTA", model_key: "SIENNA", years: 2020..2022)
  end

  test "counts heavy-duty pickups with the family they're sold as" do
    assert_equal [ "F-150", %w[F-150 F-250 F-350 F-450] ], ModelSale.family("FORD", "F-250")
    assert_equal [ "PACIFICA", %w[PACIFICA] ], ModelSale.family("CHRYSLER", "PACIFICA")
  end
end
