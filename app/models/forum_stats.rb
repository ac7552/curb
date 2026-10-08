# Each poster's reputation (the score of everything they've posted, like Reddit karma) and post count, for the author
# cards. Worked out for a page's authors in two queries.
module ForumStats
  RANKS = [ [ 200, "Veteran" ], [ 50, "Regular" ], [ 10, "Member" ], [ 0, "New member" ] ].freeze

  module_function

  def for(user_ids)
    ids = user_ids.uniq
    threads = ForumThread.visible.where(user_id: ids).group(:user_id).pluck(:user_id, Arel.sql("SUM(score)"), Arel.sql("COUNT(*)"))
    posts = ForumPost.where(hidden_at: nil, user_id: ids).group(:user_id).pluck(:user_id, Arel.sql("SUM(score)"), Arel.sql("COUNT(*)"))
    (threads + posts).each_with_object(Hash.new { |h, k| h[k] = { rep: 0, posts: 0 } }) do |(id, score, count), stats|
      stats[id][:rep] += score.to_i
      stats[id][:posts] += count
    end
  end

  def rank(posts) = RANKS.find { |floor, _| posts >= floor }.last
end
