class PlansController < ApplicationController
  allow_unauthenticated_access

  def index
    @plans = Plan.all.values
  end
end
