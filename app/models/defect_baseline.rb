# Materialized view: a category's rate across all models, per age and mileage band.
class DefectBaseline < ApplicationRecord
  include ReadOnlyView

  belongs_to :defect_category
end
