class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    redirect_to reports_path if authenticated?
  end

  def about; end
end
