# A car from the inspection data (UK MOT, Dutch RDW), not a buyer's report.
class Vehicle < ApplicationRecord
  has_many :inspections, dependent: :delete_all

  validates :source, :external_id, :country, :make, :model, :make_key, :model_key, presence: true
end
