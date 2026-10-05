class WarrantyTerm < ApplicationRecord
  COVERAGE_TYPES = %w[bumper_to_bumper powertrain corrosion emissions].freeze

  validates :country, :make_key, presence: true
  validates :coverage_type, inclusion: { in: COVERAGE_TYPES }
  validates :years, numericality: { greater_than: 0 }

  # Terms for a make and model year; a row with no year range applies to every year.
  def self.for(country:, make_key:, model_year:)
    where(country:, make_key:)
      .where("model_year_from IS NULL OR model_year_from <= ?", model_year)
      .where("model_year_to IS NULL OR model_year_to >= ?", model_year)
  end
end
