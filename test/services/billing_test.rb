require "test_helper"

class BillingTest < ActionDispatch::IntegrationTest
  STRIPE_ENV = { "STRIPE_SECRET_KEY" => "sk_test_curb", "STRIPE_WEBHOOK_SECRET" => "whsec_curb",
                 "STRIPE_PRICE_PLUS_MONTH" => "price_plus_month", "STRIPE_PRICE_PLUS_YEAR" => "price_plus_year" }.freeze

  def with_stripe
    original = STRIPE_ENV.keys.to_h { [ _1, ENV[_1] ] }
    ENV.update(STRIPE_ENV)
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  def stripe_json(body) = { headers: { "Content-Type" => "application/json" }, body: body.to_json }

  def subscription(id: "sub_1", status: "active", price: "price_plus_year", customer: "cus_1")
    { id:, object: "subscription", customer:, status:,
      items: { object: "list", data: [ { id: "si_1", object: "subscription_item", price: { id: price, object: "price" }, current_period_end: 1_830_000_000 } ] } }
  end

  def send_event(type, object, secret: STRIPE_ENV["STRIPE_WEBHOOK_SECRET"])
    payload = { id: "evt_1", object: "event", type:, data: { object: } }.to_json
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    post stripe_webhook_path, params: payload, headers: { "Content-Type" => "application/json",
                                                          "Stripe-Signature" => Stripe::Webhook::Signature.generate_header(timestamp, signature) }
  end

  test "sends someone to Stripe Checkout, making their Stripe customer once" do
    with_billing do
      with_stripe do
        customers = stub_request(:post, "https://api.stripe.com/v1/customers").to_return(stripe_json(id: "cus_1", object: "customer"))
        checkout = stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
          .with(body: hash_including("mode" => "subscription", "customer" => "cus_1", "line_items" => [ { "price" => "price_plus_year", "quantity" => "1" } ]))
          .to_return(stripe_json(id: "cs_1", object: "checkout.session", url: "https://checkout.stripe.com/c/pay/cs_1"))
        sign_in_as users(:one)

        post subscription_path(plan: "plus", interval: "year")
        post subscription_path(plan: "plus", interval: "year")

        assert_redirected_to "https://checkout.stripe.com/c/pay/cs_1"
        assert_requested customers, times: 1
        assert_requested checkout, times: 2
        assert_equal "cus_1", users(:one).reload.stripe_customer_id
      end
    end
  end

  test "Stripe's webhook moves someone onto Plus and back to Free" do
    with_stripe do
      user = users(:one)
      user.update!(stripe_customer_id: "cus_1")

      send_event("customer.subscription.updated", subscription)
      assert_response :ok
      user.reload
      assert_equal [ "plus", "active", "sub_1" ], [ user.plan, user.subscription_status, user.stripe_subscription_id ]
      assert_equal Time.zone.at(1_830_000_000), user.plan_renews_at

      send_event("customer.subscription.deleted", subscription(status: "canceled"))
      assert_equal [ "free", "canceled" ], user.reload.values_at(:plan, :subscription_status)
    end
  end

  test "an old subscription ending doesn't undo a new one" do
    with_stripe do
      user = users(:one)
      user.update!(stripe_customer_id: "cus_1", plan: "plus", stripe_subscription_id: "sub_new", subscription_status: "active")

      send_event("customer.subscription.deleted", subscription(id: "sub_old", status: "canceled"))

      assert_equal [ "plus", "sub_new" ], user.reload.values_at(:plan, :stripe_subscription_id)
    end
  end

  test "ignores webhook calls that aren't signed by Stripe" do
    with_stripe do
      users(:one).update!(stripe_customer_id: "cus_1")

      send_event("customer.subscription.updated", subscription, secret: "whsec_someone_else")

      assert_response :bad_request
      assert_equal "free", users(:one).reload.plan
    end
  end
end
