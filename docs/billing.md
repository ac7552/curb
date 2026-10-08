# Billing

**Billing is switched off** until Stripe is ready: no Plans page, no payment buttons, and no limit on checks (checks
are still counted). Turn it on by setting `CURB_BILLING: "on"` in `config/deploy.yml` and deploying; on your Mac,
run the server with `CURB_BILLING=on bin/dev`.

Plans and their limits live in `config/plans.yml`. Payments go through Stripe: Checkout takes the card,
Stripe's billing portal lets people change or cancel, and a webhook keeps each user's plan in step
(`app/services/billing.rb`). Until the Stripe keys are set, the upgrade buttons say payments aren't on yet.

## Setting up Stripe (test mode first)

1. In the Stripe dashboard, create a product called **Plus** with two recurring prices that match
   `config/plans.yml`: $1.99 monthly and $19.99 yearly.
2. Under **Settings → Billing → Customer portal**, turn on cancelling and switching between the two prices.
3. Add a webhook endpoint at `https://<your domain>/stripe/webhook` for these events:
   `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`,
   `customer.subscription.deleted`.
4. Put the keys in the app's credentials (`bin/rails credentials:edit`):

   ```yaml
   stripe:
     secret_key: sk_test_...
     webhook_secret: whsec_...
     prices:
       plus_month: price_...
       plus_year: price_...
   ```

   Or set `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_PLUS_MONTH` and `STRIPE_PRICE_PLUS_YEAR`.

To try it on your Mac, forward Stripe's events with the Stripe CLI (`stripe listen --forward-to
localhost:3000/stripe/webhook`) and use its `whsec_...` secret. Pay with Stripe's test card 4242 4242 4242 4242.

Changing a price: add a new price in Stripe, update `config/plans.yml` and the credentials, and deploy.
Existing subscribers keep the price they signed up at until you move them in Stripe.

## Claude spending

Reading guides and sorting inspection notes call Claude. Set a monthly spend limit in the Claude Console
(Settings → Limits) so the bill can't run past what you've chosen, whatever happens in the app.
