# A crash the app hit, kept for the admin panel. Crashes of the same kind (same error class, first line of our own
# code it passed through) share one row with a count, so a bug hit a thousand times is one row, not a thousand.
# Fixing it and marking it resolved clears it; if it happens again it reopens.
class ErrorEvent < ApplicationRecord
  belongs_to :user, optional: true

  BACKTRACE_LINES = 40

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :recent_first, -> { order(last_seen_at: :desc) }

  def resolved? = resolved_at.present?

  # Saves one occurrence. Never raises: a crash while saving a crash (the database being down, say) is only logged.
  def self.record(error, source: nil, context: {})
    lines = Rails.backtrace_cleaner.clean(Array(error.backtrace))
    now = Time.current
    attributes = {
      fingerprint: Digest::SHA256.hexdigest([ error.class.name, lines.first ].join("|")),
      error_class: error.class.name, message: error.message.to_s.truncate(2_000),
      backtrace: lines.first(BACKTRACE_LINES).join("\n"), source:, path: context[:path]&.truncate(500),
      request_id: context[:request_id], user_id: context[:user_id],
      occurrences: 1, first_seen_at: now, last_seen_at: now, resolved_at: nil, created_at: now, updated_at: now
    }
    upsert(attributes, unique_by: :fingerprint, on_duplicate: Arel.sql(<<~SQL.squish))
      occurrences = error_events.occurrences + 1, last_seen_at = EXCLUDED.last_seen_at, message = EXCLUDED.message,
      backtrace = EXCLUDED.backtrace, source = EXCLUDED.source, path = EXCLUDED.path, request_id = EXCLUDED.request_id,
      user_id = EXCLUDED.user_id, resolved_at = NULL, updated_at = EXCLUDED.updated_at
    SQL
  rescue StandardError => e
    Rails.logger.error("[ErrorEvent] couldn't save #{error.class}: #{e.class}: #{e.message}")
  end

  # Listens to Rails' error reporter, which hears about every crash in a page request or background job.
  class Subscriber
    def report(error, handled:, severity:, context:, source: nil)
      return if handled && severity != :error
      return if client_error?(error)
      ErrorEvent.record(error, source:, context:)
    end

    private
      # Not-found pages, bad form tokens and the like are the visitor's mistake, not a bug.
      def client_error?(error)
        ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500
      end
  end
end
