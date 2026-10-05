# Loads a set of downloaded MOT bulk files, categorizes any new phrases, then rebuilds the rate tables. The
# rebuild runs even when every phrase was already known, since new inspections change the rates either way;
# nothing else rebuilds them on a schedule.
class ImportMotFilesJob < ApplicationJob
  queue_as :default

  def perform(results:, items:, details: nil)
    summary = Importers::MotBulk.new(results:, items:, details:).call
    Rails.logger.info("[ImportMotFilesJob] #{summary.to_h}")
    CategorizeDefectPhrasesJob.perform_now(refresh: false)
    RefreshDefectRatesJob.perform_later
  end
end
