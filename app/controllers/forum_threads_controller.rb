class ForumThreadsController < ApplicationController
  include ForumPosting
  include ForumImages
  TOP_LEVEL_PER_PAGE = 50
  before_action :require_poster, only: :create
  rate_limit to: 5, within: 10.minutes, only: :create, by: -> { Current.user.id },
             with: -> { redirect_back fallback_location: community_path, alert: "That's a lot of new threads. Try again in a few minutes." }

  def show
    @thread = ForumThread.find(params[:id])
    raise ActiveRecord::RecordNotFound if @thread.hidden? && !Current.user.admin?
    @sort = ForumPost::SORTS.key?(params[:sort]) ? params[:sort] : "best"

    # Every reply, grouped under what it answers; top-level replies come a page at a time.
    posts = @thread.posts.order(ForumPost::SORTS.fetch(@sort)).includes(:user, images_attachments: :blob).to_a
    @children = posts.group_by(&:parent_id)
    top = @children.fetch(nil, [])
    @pages = [ (top.size / TOP_LEVEL_PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @pages)
    @top = top.slice((@page - 1) * TOP_LEVEL_PER_PAGE, TOP_LEVEL_PER_PAGE) || []

    @stats = ForumStats.for(posts.map(&:user_id) << @thread.user_id)
    @my_votes = Current.user.forum_votes.where(votable: [ @thread, *posts ]).to_h { [ [ _1.votable_type, _1.votable_id ], _1.value ] }
    @post = ForumPost.new
  end

  def create
    room = ForumRoom.find(params[:make], params[:model]) or raise ActiveRecord::RecordNotFound
    @thread = Current.user.forum_threads.new(params.expect(forum_thread: %i[title body]).merge(make_key: room.make_key, model_key: room.model_key))
    if attach_images(@thread) && @thread.save
      redirect_to forum_thread_path(@thread)
    else
      redirect_to community_room_path(room.make_slug, room.model_slug), alert: @thread.errors.full_messages.to_sentence
    end
  end
end
