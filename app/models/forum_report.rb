# Someone flagging a thread or reply for a moderator (Admin → Reports).
class ForumReport < ApplicationRecord
  REASONS = { "spam" => "Spam or advertising", "abuse" => "Rude, hateful or harassing", "unsafe" => "Dangerous or illegal",
              "personal" => "Shares someone's personal details", "other" => "Something else" }.freeze

  belongs_to :reporter, class_name: "User"
  belongs_to :reportable, polymorphic: true

  validates :reason, inclusion: { in: REASONS.keys }
  validates :reporter_id, uniqueness: { scope: %i[reportable_type reportable_id], message: "already reported this" }

  scope :open, -> { where(resolved_at: nil) }
end
