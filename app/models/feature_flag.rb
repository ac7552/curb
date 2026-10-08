# A switch an admin has flipped in the admin panel. See Feature for the switches and their defaults.
class FeatureFlag < ApplicationRecord
  belongs_to :updated_by, class_name: "User", optional: true

  validates :key, inclusion: { in: ->(_) { Feature.keys } }, uniqueness: true
  validates :enabled, inclusion: { in: [ true, false ] }
end
