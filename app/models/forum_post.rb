# A reply in a thread. Hidden by a moderator: it shows as removed.
class ForumPost < ApplicationRecord
  belongs_to :thread, class_name: "ForumThread", foreign_key: :forum_thread_id, counter_cache: :forum_posts_count, inverse_of: :posts
  belongs_to :user
  has_many :reports, class_name: "ForumReport", as: :reportable, dependent: :destroy

  normalizes :body, with: ->(body) { body.strip }

  validates :body, presence: true, length: { maximum: 5_000 }

  after_create_commit { thread.update_column(:last_posted_at, created_at) }

  def hidden? = hidden_at.present?
end
