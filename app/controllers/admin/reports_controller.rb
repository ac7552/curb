# Threads and replies people flagged in Our Garage, for a moderator to hide, dismiss, or ban the author over.
class Admin::ReportsController < Admin::BaseController
  def index
    @reports = ForumReport.open.order(created_at: :desc).includes(:reporter, :reportable).limit(200)
  end

  def update
    report = ForumReport.find(params[:id])
    content = report.reportable
    case params[:decision]
    when "hide"
      content.update!(hidden_at: Time.current)
      notice = "Hidden."
    when "ban"
      content.user.ban!
      notice = "#{content.user.forum_name} is banned, and everything they posted is hidden."
    else
      notice = "Dismissed."
    end
    ForumReport.open.where(reportable: content).update_all(resolved_at: Time.current)
    redirect_to admin_reports_path, notice:
  end
end
