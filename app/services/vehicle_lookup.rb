# Finds a car by VIN (US) or plate (UK via the MOT History API, Netherlands via RDW).
class VehicleLookup
  class Unavailable < StandardError; end

  def self.by_vin(vin) = Nhtsa::Vpic.new.decode(vin)

  def self.by_plate(plate, country:)
    case country
    when "GB"
      raise Unavailable, "UK plate lookup isn't set up yet. Enter the make and model instead." unless Mot::HistoryClient.configured?
      Mot::HistoryClient.new.vehicle(plate)
    when "NL" then Rdw::Client.new.vehicle(plate)
    else raise Unavailable, "Plate lookup works for UK and Dutch plates. Use the VIN instead."
    end
  end
end
