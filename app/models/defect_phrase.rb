# A unique defect wording from an inspection source, sorted into a DefectCategory once.
class DefectPhrase < ApplicationRecord
  belongs_to :defect_category, optional: true
  has_many :defects, dependent: :restrict_with_exception

  # Codes with no wording yet (an items file loaded before the lookup tables) can't be sorted.
  PLACEHOLDER = "MOT item %"

  scope :uncategorized, -> { where(categorized_at: nil) }
  scope :named, -> { where.not("text LIKE ?", PLACEHOLDER) }
end
