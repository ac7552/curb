# Loads a set of downloaded MOT bulk files, then categorizes new phrases (which refreshes the rates).
class ImportMotFilesJob < ApplicationJob
  queue_as :default

  def perform(results:, items:, details: nil)
    summary = Importers::MotBulk.new(results:, items:, details:).call
    Rails.logger.info("[ImportMotFilesJob] #{summary.to_h}")
    CategorizeDefectPhrasesJob.perform_later
  end
end
