# Materialized view: number of inspections per model, engine, age and 20k-mile band.
class InspectionCell < ApplicationRecord
  include ReadOnlyView

  MILEAGE_BAND = 20_000

  def self.band_for(miles) = [ miles.to_i, 299_999 ].min / MILEAGE_BAND

  # Models with inspection data, for the make and model pickers.
  def self.catalog
    group(:make_key, :model_key).order(:make_key, :model_key).sum(:tests)
  end
end
