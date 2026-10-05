# Materialized view: how often UK inspections record each part on a model, vs an average car the same age.
class ModelPartProfile < ApplicationRecord
  include ReadOnlyView

  belongs_to :defect_category
end
