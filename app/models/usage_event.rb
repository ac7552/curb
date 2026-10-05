class UsageEvent < ApplicationRecord
  belongs_to :user
  belongs_to :report, optional: true

  validates :kind, inclusion: { in: Plan::KINDS }

  scope :this_month, -> { where(created_at: Time.current.all_month) }
end
