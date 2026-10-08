class Admin::ErrorsController < Admin::BaseController
  def index
    @showing = params[:show] == "resolved" ? "resolved" : "open"
    @errors = (@showing == "resolved" ? ErrorEvent.resolved : ErrorEvent.unresolved).recent_first.limit(200)
  end

  def show
    @error = ErrorEvent.find(params[:id])
  end

  # Marks it fixed, or reopens it.
  def update
    error = ErrorEvent.find(params[:id])
    error.update!(resolved_at: params[:resolved] == "1" ? Time.current : nil)
    redirect_to admin_errors_path, notice: error.resolved? ? "Marked resolved. It reopens if it happens again." : "Reopened."
  end
end
