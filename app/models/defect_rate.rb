# Materialized view: inspections in a cell that recorded a defect in a category.
class DefectRate < ApplicationRecord
  include ReadOnlyView

  belongs_to :defect_category

  # The views read each other, so they refresh in this order.
  VIEWS = %w[inspection_cells defect_rates defect_baselines model_part_profiles].freeze

  def self.refresh_all!(concurrently: true)
    VIEWS.each do |view|
      populated = connection.select_value("SELECT relispopulated FROM pg_class WHERE relname = #{connection.quote(view)}")
      Scenic.database.refresh_materialized_view(view, concurrently: concurrently && populated, cascade: false)
    end
  end
end
