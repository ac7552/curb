class Inspection < ApplicationRecord
  belongs_to :vehicle
  has_many :defects, dependent: :delete_all
end
