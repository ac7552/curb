class Recall < ApplicationRecord
  belongs_to :defect_category, optional: true

  validates :campaign_number, presence: true, uniqueness: true
  validates :make_key, :model_key, :year_from, :year_to, presence: true

  scope :for_vehicle, ->(make_key:, model_key:, model_year:) {
    where(make_key:, model_key:).where("year_from <= :y AND year_to >= :y", y: model_year)
  }
end
