# Sends someone to Stripe to start a paid plan, or to Stripe's billing portal to change or cancel it.
class SubscriptionsController < ApplicationController
  before_action { head :not_found unless Billing.enabled? }
  rate_limit to: 10, within: 1.minute, with: -> { redirect_to plans_path, alert: "Try again in a minute." }

  def create
    return redirect_to(account_path, notice: "You're already on #{Current.user.plan_details.name}.") if Current.user.paid?

    plan = Plan.paid.find { _1.key == params[:plan] } or return redirect_to(plans_path)
    interval = Plan::INTERVALS.include?(params[:interval]) ? params[:interval] : "month"
    url = Billing.checkout_url(Current.user, plan:, interval:,
                               success_url: account_url(upgraded: 1), cancel_url: plans_url)
    redirect_to url, allow_other_host: true
  rescue Billing::NotConfigured
    redirect_to plans_path, alert: "Payments aren't switched on yet."
  end

  def manage
    redirect_to Billing.portal_url(Current.user, return_url: account_url), allow_other_host: true
  rescue Billing::NotConfigured
    redirect_to account_path, alert: "Payments aren't switched on yet."
  end
end
