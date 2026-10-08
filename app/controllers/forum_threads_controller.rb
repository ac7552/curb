class ForumThreadsController < ApplicationController
  include ForumPosting
  before_action :require_poster, only: :create
  rate_limit to: 5, within: 10.minutes, only: :create, by: -> { Current.user.id },
             with: -> { redirect_back fallback_location: community_path, alert: "That's a lot of new threads. Try again in a few minutes." }

  def show
    @thread = ForumThread.find(params[:id])
    raise ActiveRecord::RecordNotFound if @thread.hidden? && !Current.user.admin?
    @posts = @thread.posts.order(:created_at).includes(:user)
    @post = ForumPost.new
  end

  def create
    room = ForumRoom.find(params[:make], params[:model]) or raise ActiveRecord::RecordNotFound
    @thread = Current.user.forum_threads.new(params.expect(forum_thread: %i[title body]).merge(make_key: room.make_key, model_key: room.model_key))
    if @thread.save
      redirect_to forum_thread_path(@thread)
    else
      redirect_to community_room_path(room.make_slug, room.model_slug), alert: @thread.errors.full_messages.to_sentence
    end
  end
end
