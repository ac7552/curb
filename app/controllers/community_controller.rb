# Our Garage: a room for each model, grouped by maker. Your garage's cars link straight to their rooms.
class CommunityController < ApplicationController
  THREADS_PER_PAGE = 30

  def index
    @makes = MakeCatalog.makes(Current.user.country || "US")
    @thread_counts = ForumThread.visible.group(:make_key).count
    @my_rooms = Current.user.garage_cars.map { ForumRoom.for(_1) }.uniq
    @latest = ForumThread.visible.latest.includes(:user).limit(8)
  end

  def make
    @make_key = ForumRoom.make_key_for(params[:make]) or raise ActiveRecord::RecordNotFound
    @rooms = ForumRoom.listed_model_keys(@make_key).map { ForumRoom.new(make_key: @make_key, model_key: _1) }
    @thread_counts = ForumThread.visible.where(make_key: @make_key).group(:model_key).count
    @latest = ForumThread.visible.where(make_key: @make_key).latest.includes(:user).limit(10)
  end

  def room
    @room = ForumRoom.find(params[:make], params[:model]) or raise ActiveRecord::RecordNotFound
    @page = [ params[:page].to_i, 1 ].max
    @threads = @room.threads.latest.includes(:user).offset((@page - 1) * THREADS_PER_PAGE).limit(THREADS_PER_PAGE + 1).to_a
    @more = @threads.size > THREADS_PER_PAGE
    @threads = @threads.first(THREADS_PER_PAGE)
    @thread = ForumThread.new
  end
end
