# A discussion in a model's room. Hidden by a moderator: only admins see it.
class ForumThread < ApplicationRecord
  include ForumContent

  has_many :posts, class_name: "ForumPost", dependent: :destroy

  normalizes :title, with: ->(title) { title.squish }
  normalizes :body, with: ->(body) { body.strip }

  validates :make_key, :model_key, presence: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 10_000 }

  before_validation { self.last_posted_at ||= Time.current }

  scope :visible, -> { where(hidden_at: nil) }
  scope :latest, -> { order(last_posted_at: :desc) }

  # Ways to sort a room, as Reddit does. Hot: score, fading with age (a day-old thread needs about 10× the votes).
  SORTS = {
    "hot" => Arel.sql("LOG(GREATEST(ABS(forum_threads.score), 1)) * SIGN(forum_threads.score) + " \
                      "EXTRACT(EPOCH FROM forum_threads.created_at) / 45000 DESC"),
    "new" => { created_at: :desc },
    "top" => { score: :desc, created_at: :desc },
    "active" => { last_posted_at: :desc }
  }.freeze

  def self.sorted(sort) = order(SORTS.fetch(sort) { SORTS["hot"] })

  def room = ForumRoom.new(make_key:, model_key:)
end
