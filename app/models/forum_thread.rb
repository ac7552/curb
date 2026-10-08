# A discussion in a model's room. Hidden by a moderator: only admins see it.
class ForumThread < ApplicationRecord
  belongs_to :user
  has_many :posts, class_name: "ForumPost", dependent: :destroy
  has_many :reports, class_name: "ForumReport", as: :reportable, dependent: :destroy

  normalizes :title, with: ->(title) { title.squish }
  normalizes :body, with: ->(body) { body.strip }

  validates :make_key, :model_key, presence: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 10_000 }

  before_validation { self.last_posted_at ||= Time.current }

  scope :visible, -> { where(hidden_at: nil) }
  scope :latest, -> { order(last_posted_at: :desc) }

  def room = ForumRoom.new(make_key:, model_key:)
  def hidden? = hidden_at.present?
end
