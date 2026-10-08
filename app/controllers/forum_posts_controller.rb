class ForumPostsController < ApplicationController
  include ForumPosting
  include ForumImages
  before_action :require_poster
  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id },
             with: -> { redirect_back fallback_location: community_path, alert: "Slow down a moment, then try again." }

  def create
    thread = ForumThread.visible.find(params[:forum_thread_id])
    post = thread.posts.new(params.expect(forum_post: %i[body parent_id]).merge(user: Current.user))
    if attach_images(post) && post.save
      redirect_to forum_thread_path(thread, anchor: "post-#{post.id}")
    else
      redirect_to forum_thread_path(thread, anchor: "reply"), alert: post.errors.full_messages.to_sentence
    end
  end
end
