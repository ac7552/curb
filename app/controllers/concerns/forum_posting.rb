# Who may post in Our Garage: people with a name on their account (shown as "Sam R.") who haven't been banned.
module ForumPosting
  extend ActiveSupport::Concern

  private
    def require_poster
      if Current.user.banned?
        redirect_back fallback_location: community_path, alert: "Your account can't post in Our Garage."
      elsif Current.user.first_name.blank? || Current.user.last_name.blank?
        redirect_to account_path, alert: "Add your first and last name before posting. Others see your first name and last initial."
      end
    end
end
