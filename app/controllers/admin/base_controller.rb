# The admin panel. Anyone who isn't an admin gets "not found", so the panel doesn't announce itself.
class Admin::BaseController < ApplicationController
  before_action { head :not_found unless Current.user&.admin? }
end
