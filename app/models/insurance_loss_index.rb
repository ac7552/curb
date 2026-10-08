# How a model's insurance claims compare with the average vehicle (100 = average). Empty until there's data we're
# allowed to use: HLDI's needs their written permission for a commercial site. With no row, a model counts as average.
class InsuranceLossIndex < ApplicationRecord
  self.table_name = "insurance_loss_indexes"

  KINDS = %i[injury collision theft property_damage].freeze

  validates :make_key, :model_key, :source, presence: true
  validates :year_from, :year_to, numericality: { only_integer: true }
  validates(*KINDS, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true)

  def self.for(make_key:, model_key:, model_year:)
    where(make_key:, model_key:).where(year_from: ..model_year, year_to: model_year..).order(year_from: :desc).first
  end

  # The indexes PremiumCalculator takes, leaving out any we don't have.
  def to_hldi = KINDS.to_h { [ _1, self[_1] ] }.compact
end
