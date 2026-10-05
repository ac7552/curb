# Stripe tells us here when a subscription starts, changes or ends. Every request is checked against the
# webhook signing secret, so only Stripe can change anyone's plan.
class StripeWebhooksController < ActionController::API
  def create
    event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], Billing.webhook_secret.to_s)
    Billing.handle(event)
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end
