# Flagging a thread or reply for a moderator.
class ForumReportsController < ApplicationController
  REPORTABLE = { "ForumThread" => ForumThread, "ForumPost" => ForumPost }.freeze
  rate_limit to: 10, within: 10.minutes, by: -> { Current.user.id }

  def create
    model = REPORTABLE.fetch(params[:reportable_type]) { raise ActiveRecord::RecordNotFound }
    reportable = model.find(params[:reportable_id])
    report = Current.user.forum_reports.new(reportable:, reason: params[:reason])
    thread = reportable.is_a?(ForumThread) ? reportable : reportable.thread
    if report.save
      redirect_to forum_thread_path(thread), notice: "Thanks. A moderator will take a look."
    else
      redirect_to forum_thread_path(thread), alert: report.errors.full_messages.to_sentence
    end
  end
end
