# The service schedule read from a maker's maintenance guide for one car (year, make, model). Filled in
# ahead of time from a developer's machine (bin/rails curb:guides:prefill) and loaded from
# db/seeds/maintenance_guides, so every check of that car can use it. See MaintenanceGuides::Prefill.
class MaintenanceGuide < ApplicationRecord
  STATUSES = %w[ok needs_review].freeze

  validates :make_key, :model_key, :make, :model, :url, :title, presence: true
  validates :model_year, numericality: { only_integer: true }
  validates :status, inclusion: { in: STATUSES }

  scope :trusted, -> { where(status: "ok") }

  def self.for(make:, model:, model_year:)
    find_by(make_key: VehicleName.make_key(make), model_key: VehicleName.model_key(model), model_year:)
  end

  # The priced schedule with this guide's intervals in place of the usual ones. Prices stay Curb's, since
  # guides don't have them; items the guide doesn't mention keep the usual interval. When the guide gives
  # an item per engine and we don't know which engine, the most frequent is used, so upkeep isn't understated.
  def apply_to(items)
    items.map do |item|
      row = guided_row(item.name) or next item
      item.dup.tap { |copy| copy.assign_attributes(interval_miles: row["interval_miles"], interval_months: row["interval_months"]) }
    end
  end

  # Names of the schedule items this guide sets, with the page each is on.
  def pages_by_item
    rows.group_by { _1["name"] }.transform_values { |same| same.filter_map { _1["source_page"] }.uniq.sort }
  end

  # The guide's other intervals for an item, when it differs by engine or version: [{ "interval_miles",
  # "interval_months", "applies_to" }], without the one used.
  def other_versions(name)
    used = guided_row(name)
    intervals(name).reject { _1.values_at("interval_miles", "interval_months") == used&.values_at("interval_miles", "interval_months") }
                   .uniq { _1.values_at("interval_miles", "interval_months") }
  end

  private
    def intervals(name) = rows.select { _1["name"] == name && (_1["interval_miles"] || _1["interval_months"]) }

    def guided_row(name)
      intervals(name).min_by { [ _1["interval_miles"] || Float::INFINITY, _1["interval_months"] || Float::INFINITY ] }
    end
end
