# New cars of a model sold in the US in a calendar year (see Importers::WikipediaSales).
class ModelSale < ApplicationRecord
  # Makers report some models only as a family (light- and heavy-duty pickups together). Sales are stored
  # under the first key; complaints for every key in the family are counted against them.
  FAMILIES = {
    "FORD" => [ %w[F-150 F-250 F-350 F-450] ],
    "RAM" => [ %w[1500 2500 3500] ],
    "DODGE" => [ %w[RAM] ],
    "CHEVROLET" => [ %w[SILVERADO] ],
    "GMC" => [ %w[SIERRA] ]
  }.freeze

  # [sales key, every key counted against its sales] for a model.
  def self.family(make_key, model_key)
    members = FAMILIES.fetch(make_key, []).find { |keys| keys.include?(model_key) } || [ model_key ]
    [ members.first, members ]
  end

  validates :make_key, :model_key, :year, :source, presence: true
  validates :units, numericality: { greater_than: 0 }

  # Cars sold over a range of years, or nil when any year is missing (a partial count would
  # make complaints per car look worse than they are).
  def self.units_for(make_key:, model_key:, years:)
    rows = where(make_key:, model_key:, year: years).pluck(:year, :units).to_h
    rows.size == years.count ? rows.values.sum : nil
  end
end
