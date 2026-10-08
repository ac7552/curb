class Admin::DashboardController < Admin::BaseController
  def show
    @users = User.count
    @new_users = User.where(created_at: 7.days.ago..).count
    @checks_today = UsageEvent.where(kind: "check", created_at: Time.current.all_day).count
    @checks_week = UsageEvent.where(kind: "check", created_at: 7.days.ago..).count
    @open_errors = ErrorEvent.unresolved.count
    @open_reports = ForumReport.open.count
    @recent_errors = ErrorEvent.unresolved.recent_first.limit(5)
  end
end
