class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Tells the error reporter where a crash happened and to whom, for the admin panel's Errors page. The address is
  # filtered like the logs are, and password-reset tokens are blanked, since they work as a password for a while.
  before_action do
    path = request.filtered_path.sub(%r{\A/passwords/[^/?]+}, "/passwords/[FILTERED]")
    Rails.error.set_context(path:, request_id: request.request_id, user_id: Current.user&.id)
  end
end
