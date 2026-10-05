class Defect < ApplicationRecord
  KINDS = %w[fail advisory].freeze

  belongs_to :inspection
  belongs_to :defect_phrase

  validates :kind, inclusion: { in: KINDS }
end
