# A fix a car maker sent dealers for a known problem (see Importers::NhtsaBulletins).
class ServiceBulletin < ApplicationRecord
  scope :programs, -> { where.not(program_kind: nil) }

  # Free repairs the maker has already agreed to pay for on this car: warranty extensions, customer
  # satisfaction programmes, special policy adjustments. Unlike a recall these are never mailed out
  # and a dealer is not obliged to raise them, so an owner can pay for a repair that was covered.
  #
  # One row per document: NHTSA repeats a programme for every model year it covers, and the same
  # wording is filed under several document ids, so both are collapsed.
  def self.programs_for(make_key:, model_key:, model_year:)
    programs
      .where(make_key:, model_key:, model_year:)
      .order(:program_kind, :title)
      .uniq { |bulletin| bulletin.title }
  end

  def program_label = BulletinProgram.label(program_kind)
end
