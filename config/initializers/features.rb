# Features that can be switched on and off without changing code.
#
# Billing: the Plus plan, payment pages and monthly limits on checks. Off until Stripe is set up (docs/billing.md);
# turn on with CURB_BILLING=on (config/deploy.yml for the live site). While it's off nobody is limited, and checks
# are still counted, so there are usage numbers to price from when it goes on.
Rails.application.config.x.billing = ActiveModel::Type::Boolean.new.cast(ENV.fetch("CURB_BILLING", "off"))
