require "test_helper"

class Importers::WikipediaSalesTest < ActiveSupport::TestCase
  HTML = <<~HTML
    <table class="wikitable"><tr><th>Calendar year</th><th>U.S.</th><th>Canada</th></tr>
      <tr><td>2017</td><td>118,274[12]</td><td>9,000</td></tr>
      <tr><td>2018</td><td>118,322</td><td>8,000</td></tr>
      <tr><td>2019</td><td>97,705</td><td>7,000</td></tr></table>
    <table class="wikitable"><tr><th>Year</th><th>US</th></tr>
      <tr><td>2017</td><td>4,000</td></tr><tr><td>2018</td><td>5,000</td></tr><tr><td>2019</td><td>6,000</td></tr></table>
    <table class="wikitable"><tr><th>Year</th><th>Europe</th></tr><tr><td>2017</td><td>500,000</td></tr></table>
  HTML

  test "reads the biggest US sales table on a page" do
    sales = Importers::WikipediaSales.new(overrides: {}, pause: 0).us_sales(HTML)

    assert_equal({ 2017 => 118_274, 2018 => 118_322, 2019 => 97_705 }, sales)
  end

  test "only trusts search results whose title names the model" do
    importer = Importers::WikipediaSales.new(overrides: {}, pause: 0)
    assert importer.names_model?("Chrysler Pacifica (minivan)", "CHRYSLER", "PACIFICA")
    assert importer.names_model?("Honda CR-V", "HONDA", "CR-V")
    assert importer.names_model?("Jeep Grand Cherokee (WL)", "JEEP", "GRAND CHEROKEE")
    assert importer.names_model?("Mazda3", "MAZDA", "MAZDA3")
    assert_not importer.names_model?("Jeep Grand Cherokee", "JEEP", "CHEROKEE")
    assert_not importer.names_model?("Ford Mustang Mach-E", "FORD", "MUSTANG")
    assert_not importer.names_model?("GMC Acadia", "GMC", "TERRAIN")
  end

  test "finds the US column under a two-row heading or inside a longer heading" do
    importer = Importers::WikipediaSales.new(overrides: {}, pause: 0)
    two_rows = <<~HTML
      <table class="wikitable"><tr><th rowspan="2">Year</th><th colspan="2">Sales</th></tr><tr><th>U.S.</th><th>Japan</th></tr>
      <tr><td>2017</td><td>127,563</td><td>20,000</td></tr><tr><td>2018</td><td>150,622</td><td>1</td></tr><tr><td>2019</td><td>154,545</td><td>1</td></tr></table>
    HTML
    named = <<~HTML
      <table class="wikitable"><tr><th>Calendar year</th><th>Explorer (US)</th><th>(US) Police Interceptor</th></tr>
      <tr><td>2017</td><td>271,131</td><td>30,000</td></tr><tr><td>2018</td><td>261,571</td><td>1</td></tr><tr><td>2019</td><td>187,146</td><td>1</td></tr></table>
    HTML

    assert_equal 127_563, importer.us_sales(two_rows)[2017]
    assert_equal 271_131, importer.us_sales(named)[2017]
  end
end
