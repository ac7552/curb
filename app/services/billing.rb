# Plus subscriptions through Stripe. Stripe hosts the card form (Checkout) and the page where people change or
# cancel (the billing portal); we never see card details. Its webhooks tell us when a subscription starts,
# changes or ends, and sync_subscription writes that onto the user, so pages read the plan from our database.
#
# Keys come from credentials (stripe.secret_key, stripe.webhook_secret, stripe.prices.*) or the matching
# STRIPE_* environment variables. Until they're set, configured? is false and the upgrade buttons say so.
module Billing
  class NotConfigured < StandardError; end

  # Statuses that keep someone on their paid plan. past_due is Stripe retrying a failed card; cutting
  # access the moment a card fails would punish people for an expired card.
  PAID_STATUSES = %w[active trialing past_due].freeze

  module_function

  # Whether plans and payments are switched on (config/initializers/features.rb).
  def enabled? = Rails.configuration.x.billing

  def secret_key = ENV["STRIPE_SECRET_KEY"].presence || Rails.application.credentials.dig(:stripe, :secret_key)
  def webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"].presence || Rails.application.credentials.dig(:stripe, :webhook_secret)

  def configured? = secret_key.present? && Plan.paid.all? { |plan| Plan::INTERVALS.all? { plan.stripe_price_id(_1).present? } }

  def client
    raise NotConfigured, "Stripe keys aren't set" unless configured?
    Stripe::StripeClient.new(secret_key)
  end

  # Where to send someone to pay for a plan. Their Stripe customer is made on the first visit and reused.
  def checkout_url(user, plan:, interval:, success_url:, cancel_url:)
    stripe = client
    price = plan.stripe_price_id(interval) or raise ArgumentError, "No Stripe price for #{plan.key} each #{interval}"
    stripe.v1.checkout.sessions.create(
      mode: "subscription",
      customer: customer_id(user),
      client_reference_id: user.id.to_s,
      line_items: [ { price:, quantity: 1 } ],
      success_url:, cancel_url:,
      allow_promotion_codes: true
    ).url
  end

  # Stripe's page for changing the card, switching monthly and yearly, or cancelling.
  def portal_url(user, return_url:)
    client.v1.billing_portal.sessions.create(customer: customer_id(user), return_url:).url
  end

  def customer_id(user)
    user.stripe_customer_id || begin
      customer = client.v1.customers.create(email: user.email_address, name: user.name, metadata: { user_id: user.id })
      user.update_columns(stripe_customer_id: customer.id, updated_at: Time.current)
      customer.id
    end
  end

  # A verified event from Stripe's webhook. Returns the user it changed, or nil when it isn't one we act on.
  def handle(event)
    case event.type
    when "checkout.session.completed"
      session = event.data.object
      return unless session.mode == "subscription" && session.subscription
      sync_subscription(client.v1.subscriptions.retrieve(session.subscription).to_hash)
    when "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
      sync_subscription(event.data.object.to_hash)
    end
  end

  # Puts a Stripe subscription (as a hash) onto its user: the plan its price belongs to while it's paid up,
  # Free once it ends.
  def sync_subscription(subscription)
    user = User.find_by(stripe_customer_id: subscription[:customer]) or return
    item = subscription.dig(:items, :data, 0)
    plan = Plan.for_stripe_price(item&.dig(:price, :id))
    paid = PAID_STATUSES.include?(subscription[:status]) && plan
    # An old subscription ending after the person has started a new one changes nothing.
    return user if !paid && user.paid? && user.stripe_subscription_id.present? && user.stripe_subscription_id != subscription[:id]

    # Newer Stripe API versions keep the renewal date on the item rather than the subscription.
    renews_at = subscription[:current_period_end] || item&.dig(:current_period_end)

    user.update_columns(
      plan: paid ? plan.key : "free",
      stripe_subscription_id: subscription[:id],
      subscription_status: subscription[:status],
      plan_renews_at: (Time.zone.at(renews_at) if paid && renews_at),
      updated_at: Time.current
    )
    user
  end
end
