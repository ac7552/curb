class PlansController < ApplicationController
  before_action { head :not_found unless Billing.enabled? }
  allow_unauthenticated_access

  def index
    @plans = Plan.all.values
  end
end
