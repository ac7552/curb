# What a VIN or plate lookup found about a car, before the buyer adds their own numbers.
VehicleMatch = Data.define(:source, :make, :model, :model_year, :engine, :fuel_type, :first_used_on, :history) do
  def initialize(source:, make:, model:, model_year: nil, engine: nil, fuel_type: nil, first_used_on: nil, history: nil)
    model_year ||= first_used_on&.year
    super
  end

  def as_json(*) = to_h.merge(first_used_on: first_used_on&.iso8601)
end
