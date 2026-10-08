# One person's up (+1) or down (-1) vote on a thread or reply. The thread's or reply's score moves with it, in one
# atomic update, so votes cast at the same moment can't be lost.
class ForumVote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [ -1, 1 ] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }
  validate :not_your_own

  after_create { move_score(value) }
  after_update { move_score(value - value_before_last_save) if saved_change_to_value? }
  after_destroy { move_score(-value) }

  # Sets someone's vote: 1, -1, or 0 to take it back. Returns the new score.
  def self.cast(user:, votable:, value:)
    vote = find_or_initialize_by(user:, votable:)
    value.zero? ? (vote.destroy if vote.persisted?) : vote.update!(value:)
    votable.reload.score
  end

  private
    def move_score(delta) = votable.class.update_counters(votable_id, score: delta)

    def not_your_own
      errors.add(:base, "You can't vote on your own post") if votable && votable.user_id == user_id
    end
end
