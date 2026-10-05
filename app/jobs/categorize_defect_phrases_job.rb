# Categorizes every defect phrase that hasn't been categorized yet, then rebuilds the rate tables.
class CategorizeDefectPhrasesJob < ApplicationJob
  queue_as :default

  retry_on Anthropic::Errors::RateLimitError, Anthropic::Errors::APIConnectionError,
           Anthropic::Errors::InternalServerError, wait: :polynomially_longer, attempts: 5

  def perform(refresh: true)
    categorizer = DefectCategorizer.new
    count = 0
    DefectPhrase.uncategorized.named.in_batches(of: 1_000) { |batch| count += categorizer.categorize(batch.to_a) }
    Rails.logger.info("[CategorizeDefectPhrasesJob] categorized #{count} phrases")
    waiting = DefectPhrase.uncategorized.where("text LIKE ?", DefectPhrase::PLACEHOLDER).count
    Rails.logger.warn("[CategorizeDefectPhrasesJob] #{waiting} defect codes have no wording yet; load the MOT lookup tables") if waiting.positive?
    RefreshDefectRatesJob.perform_later if refresh && count.positive?
  end
end
