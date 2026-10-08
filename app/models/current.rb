class Current < ActiveSupport::CurrentAttributes
  attribute :session, :feature_states
  delegate :user, to: :session, allow_nil: true
end
