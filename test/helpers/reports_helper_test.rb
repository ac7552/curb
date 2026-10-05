require "test_helper"

class ReportsHelperTest < ActionView::TestCase
  include ApplicationHelper
  test "splits yearly amounts so they add up to the total shown" do
    assert_equal [ 1_140, 920, 1_800 ], split_to_total([ 1_135, 916, 1_767 ], 3_860)
    assert_equal 3_860, split_to_total([ 1_135, 916, 1_767 ], 3_860).sum
  end

  test "says how many records a finding rests on, and warns when it's only a few" do
    report = Report.new(country: "US", make: "Toyota", model: "Tacoma", model_year: 2019,
                        results: { data: { model_tests: 67 } }, live_data: { owner_reports: { complaints: 275 } })

    assert_match "(67 inspections)", cite_with_count(:mot, report)
    assert_match "rough guess", cite_with_count(:mot, report)
    assert_match "(275 reports)", cite_with_count(:complaints, report)
    assert_no_match "rough guess", cite_with_count(:complaints, report)
  end

  test "rounds money the way people say it" do
    market = Market.fetch("US")
    assert_equal "$19,300", about_money(19_317, market)
    assert_equal "$230", about_money(234, market)
    assert_equal "$90", about_money(92, market)
  end

  test "says chances as cars out of ten, or 1 out of N when rarer" do
    assert_equal "3 out of 10 cars like this", cars_like_this(0.33)
    assert_equal "about 1 out of 19 cars like this", cars_like_this(0.052)
    assert_equal "about 1 out of 70 cars like this", cars_like_this(0.0145)
    assert_equal "almost no cars like this", cars_like_this(0.004)
    assert_nil out_of_ten(0.06)
  end

  test "puts likelihood in words" do
    assert_equal "Likely", likelihood_word(0.4)
    assert_equal "Could happen", likelihood_word(0.15)
    assert_equal "Not likely", likelihood_word(0.02)
  end

  test "writes weak-spot evidence as one plain sentence" do
    assert_equal "UK safety checks find it 2 times as often as on other cars this age.",
                 weak_spot_sentence({ source: "uk", ratio: 1.9 }, "shocks", "BMW")
    assert_equal "US owners report it 3 times as often as owners of most cars.",
                 weak_spot_sentence({ source: "owners", per_car_ratio: 3.1 }, "engine", "BMW")
    assert_equal "BMW sent dealers 31 fixes for the water pump. Most cars get far fewer.",
                 weak_spot_sentence({ source: "bulletins", theme: "water-pump", count: 31, mix_ratio: 3.2 }, "cooling system", "BMW")
    assert_equal "more often than", how_often(1.4)
    assert_equal "3 times as often as", how_often(3.2)
    assert_equal "more than 4 times as often as", how_often(6)
    assert_equal "about twice as many", how_many(1.9)
  end
end
