# Keeps every crash for the admin panel's Errors page (ErrorEvent).
Rails.application.config.after_initialize do
  Rails.error.subscribe(ErrorEvent::Subscriber.new)
end
