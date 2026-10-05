class ServiceItem < ApplicationRecord
  # Jobs an electric car doesn't have.
  ENGINE_ONLY = [ "Oil and filter change", "Spark plugs", "Engine air filter", "Transmission fluid", "Timing belt" ].freeze

  validates :name, presence: true
  validate :has_an_interval

  # The generic schedule, with any make- or model-specific item replacing the generic one of the same name.
  def self.schedule_for(make_key:, model_key:)
    items = where(make_key: nil, model_key: nil)
      .or(where(make_key:, model_key: nil))
      .or(where(make_key:, model_key:))
      .to_a
    items.group_by(&:name).map do |_, same_name|
      same_name.max_by { |item| [ item.make_key ? 1 : 0, item.model_key ? 1 : 0 ] }
    end.sort_by(&:name)
  end

  def cost(labor_rate:, market:)
    (labor_hours * labor_rate + parts_cost_usd * market.usd_rate).to_f.round
  end

  private
    def has_an_interval
      errors.add(:base, "needs an interval in miles or months") if interval_miles.blank? && interval_months.blank?
    end
end
