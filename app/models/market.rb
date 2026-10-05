# Per-country settings. Amounts in reference tables are stored in USD and converted with a fixed,
# approximate rate; labor rates are stored in the local currency.
class Market
  KM_PER_MILE = 1.609344

  Settings = Data.define(:code, :name, :currency, :symbol, :usd_rate, :distance_unit, :default_miles_per_year, :lookup)

  ALL = {
    "US" => Settings.new(code: "US", name: "United States", currency: "USD", symbol: "$", usd_rate: 1.0,
                         distance_unit: "mi", default_miles_per_year: 13_500, lookup: :vin),
    "GB" => Settings.new(code: "GB", name: "United Kingdom", currency: "GBP", symbol: "£", usd_rate: 0.79,
                         distance_unit: "mi", default_miles_per_year: 7_400, lookup: :plate),
    "NL" => Settings.new(code: "NL", name: "Netherlands", currency: "EUR", symbol: "€", usd_rate: 0.92,
                         distance_unit: "km", default_miles_per_year: 8_100, lookup: :plate)
  }.freeze

  def self.fetch(code)
    ALL.fetch(code.to_s.upcase) { ALL.fetch("US") }
  end

  def self.codes = ALL.keys

  def self.to_miles(distance, code)
    return if distance.nil?
    fetch(code).distance_unit == "km" ? (distance / KM_PER_MILE).round : distance.round
  end

  def self.from_miles(miles, code)
    return if miles.nil?
    fetch(code).distance_unit == "km" ? (miles * KM_PER_MILE).round : miles.round
  end
end
