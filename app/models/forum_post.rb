# A reply in a thread, to the thread itself or to another reply. Hidden by a moderator: it shows as removed, and its
# replies stay.
class ForumPost < ApplicationRecord
  include ForumContent

  belongs_to :thread, class_name: "ForumThread", foreign_key: :forum_thread_id, counter_cache: :forum_posts_count, inverse_of: :posts
  belongs_to :parent, class_name: "ForumPost", optional: true
  has_many :replies, class_name: "ForumPost", foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy

  normalizes :body, with: ->(body) { body.strip }

  validates :body, presence: true, length: { maximum: 5_000 }
  validate :parent_in_the_same_thread

  after_create_commit { thread.update_column(:last_posted_at, created_at) }

  SORTS = { "best" => { score: :desc, created_at: :asc }, "new" => { created_at: :desc }, "old" => { created_at: :asc } }.freeze

  private
    def parent_in_the_same_thread
      errors.add(:parent, "isn't in this thread") if parent && parent.forum_thread_id != forum_thread_id
    end
end
