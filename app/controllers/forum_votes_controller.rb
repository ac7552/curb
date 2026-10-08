# Up- and down-votes on threads and replies. Answers with the new score, for the vote buttons to show.
class ForumVotesController < ApplicationController
  VOTABLE = { "ForumThread" => ForumThread, "ForumPost" => ForumPost }.freeze
  rate_limit to: 60, within: 1.minute, by: -> { Current.user.id }, with: -> { head :too_many_requests }

  def create
    return head(:forbidden) if Current.user.banned?
    votable = VOTABLE.fetch(params[:votable_type]) { raise ActiveRecord::RecordNotFound }.where(hidden_at: nil).find(params[:votable_id])
    value = params[:value].to_i.clamp(-1, 1)
    score = ForumVote.cast(user: Current.user, votable:, value:)
    render json: { score:, value: }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end
end
