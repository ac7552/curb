# Read-only view of a report for anyone with its link.
class SharedReportsController < ApplicationController
  allow_unauthenticated_access

  def show
    @report = Report.find_by!(share_token: params[:token])
    @shared = true
    render "reports/show"
  end
end
