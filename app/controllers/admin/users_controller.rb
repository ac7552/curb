class Admin::UsersController < Admin::BaseController
  def ban
    user = User.find(params[:id])
    return redirect_to(admin_users_path, alert: "Admins can't be banned.") if user.admin?
    user.ban!
    redirect_to admin_users_path(q: params[:q]), notice: "#{user.email_address} can't post in Our Garage anymore, and their posts are hidden."
  end

  # Lets them post again. Their old posts stay hidden; unhide any by hand from Reports if needed.
  def unban
    user = User.find(params[:id])
    user.unban!
    redirect_to admin_users_path(q: params[:q]), notice: "#{user.email_address} can post again."
  end

  LIMIT = 200

  def index
    @query = params[:q].to_s.strip
    users = User.order(created_at: :desc)
    if @query.present?
      pattern = "%#{User.sanitize_sql_like(@query)}%"
      users = users.where("email_address ILIKE :p OR first_name ILIKE :p OR last_name ILIKE :p", p: pattern)
    end
    @total = users.count
    @users = users.limit(LIMIT).to_a

    ids = @users.map(&:id)
    @checks_this_month = UsageEvent.this_month.where(kind: "check", user_id: ids).group(:user_id).count
    @saved_checks = Report.where(user_id: ids).group(:user_id).count
    @last_seen = Session.where(user_id: ids).group(:user_id).maximum(:updated_at)
  end
end
