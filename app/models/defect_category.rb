class DefectCategory < ApplicationRecord
  WARRANTY_TYPES = %w[bumper_to_bumper powertrain corrosion emissions none].freeze

  has_many :defect_phrases, dependent: :nullify
  has_many :recalls, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  validates :warranty_type, inclusion: { in: WARRANTY_TYPES }

  scope :repairs, -> { where(wear_item: false) }

  # Typical repair bill in the buyer's currency.
  def repair_cost(labor_rate:, market:)
    (labor_hours * labor_rate + parts_cost_usd * market.usd_rate).to_f.round
  end

  # First category whose keywords appear in the text; used when AI categorizing is off, and for recalls.
  def self.match(text, categories = all.to_a)
    haystack = text.to_s.downcase
    categories
      .flat_map { |category| category.keywords.map { |word| [ category, word.downcase ] } }
      .select { |_, word| haystack.match?(/\b#{Regexp.escape(word)}/) }
      .max_by { |_, word| word.length }
      &.first
  end
end
