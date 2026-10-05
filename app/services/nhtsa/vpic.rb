module Nhtsa
  # VIN to make, model, year and engine. Free, no key. https://vpic.nhtsa.dot.gov/api/
  class Vpic
    URL = "https://vpic.nhtsa.dot.gov/api/"

    def initialize(connection: HttpClient.build(URL)) = @connection = connection

    # Every model NHTSA lists for a make and model year ("Model S", "Model 3", ...). Kept in memory per
    # make and year; raises HttpClient::Error when NHTSA can't be reached.
    def models(make:, model_year:)
      key = [ make.to_s.downcase.strip, model_year.to_i ]
      self.class.models_cache[key] ||= HttpClient
        .get(@connection, "vehicles/GetModelsForMakeYear/make/#{ERB::Util.url_encode(key.first)}/modelyear/#{key.last}", { format: "json" })
        .fetch("Results", []).map { |row| row["Model_Name"].to_s.strip }.reject(&:empty?).uniq.sort
    end

    def self.models_cache = @models_cache ||= {}

    # Whether a typed model is one of NHTSA's models: the same model family ("Grand Cherokee L" is a
    # Grand Cherokee), or a trim of it for makers that list trims ("3 Series" covers "330i").
    def self.listed?(make:, model:, models:)
      key = VehicleName.model_key(model)
      family = VehicleName.trim_family_pattern(make, model)
      models.any? do |listed|
        listed_key = VehicleName.model_key(listed)
        listed_key == key || (family && listed_key.match?(Regexp.new(family)))
      end
    end

    def decode(vin)
      row = HttpClient.get(@connection, "vehicles/DecodeVinValues/#{vin}", { format: "json" }).fetch("Results", []).first || {}
      return if row["Make"].blank? || row["Model"].blank?

      VehicleMatch.new(
        source: "NHTSA vPIC",
        make: row["Make"].titleize,
        model: row["Model"],
        model_year: row["ModelYear"].presence&.to_i,
        engine: row["DisplacementL"].presence && format("%.1fL", row["DisplacementL"].to_f),
        fuel_type: row["FuelTypePrimary"].presence
      )
    end
  end
end
