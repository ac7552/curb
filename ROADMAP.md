# Curb Roadmap

The work ahead, in recommended build order. Curb's core engine, data importers (UK MOT, US NHTSA,
Dutch RDW), model weak-spot profiles, the garage/forums layer, and a Stripe billing path all exist;
the items below are what's needed to make the numbers trustworthy and open the product up. Statuses are
honest: nothing below is finished.

| # | Feature | Value | Effort | Status |
|---|---------|-------|--------|--------|
| 1 | Replace starter reference data with real figures | High | Medium | Planned |
| 2 | Confidence calibration + accuracy harness | High | Medium–High | Planned |
| 3 | Turn on billing | High | Medium | Built, switched off |
| 4 | Insurance estimate → shippable report section | Medium–High | Medium | Admin preview only |
| 5 | Lot-ready mobile flow | High | Medium | Planned |
| 6 | Wider US "per car sold" coverage | Medium | Medium | Partial |
| 7 | Netherlands (APK/RDW) profile parity | Medium | Medium–High | Planned |
| 8 | Public shared reports | Medium | Low–Medium | Scaffolded |

---

### 1. Replace starter reference data with real figures
The README says it outright: the warranty terms, service schedule and labor/repair costs in
[`db/seeds/*.yml`](db/seeds) are starter values. Before any figure is shown without a "demo" caveat,
replace repair costs with CarMD or HaynesPro data, check each warranty term against the manufacturer,
and verify the service schedule. This is the single biggest lever on trust — every report leans on
`app/models/true_cost/maintenance_plan.rb` and `coverage.rb`. Do it first.

### 2. Confidence calibration + accuracy harness
Every figure is labeled with a confidence level, but those levels aren't yet validated. Build a harness
that back-tests `app/models/true_cost/defect_odds.rb` and `calculator.rb` against held-out MOT years
(predict year N from years before it, measure error), then tune the smoothing constant (k = 50 today)
and the confidence bands from the measured error instead of by hand. Pairs naturally with #1.

### 3. Turn on billing
Plans, payments, check limits and Stripe webhooks are already built behind a feature switch
(`plans_controller.rb`, `subscriptions_controller.rb`, `stripe_webhooks_controller.rb`, see
[`docs/billing.md`](docs/billing.md)) and switched off. Work ahead: finalize the plan tiers and free
check limit, move Stripe from test to live keys, exercise the full subscribe → webhook → entitlement
path end to end, and add dunning/cancellation handling before flipping the switch on.

### 4. Insurance estimate → shippable report section
The premium estimate exists only as an admin preview today. Promote it to a real report section: source
rating inputs that can stand behind a shown number, label its confidence like the other figures, and
fold it into the "true cost to own" total rather than sitting beside it.

### 5. Lot-ready mobile flow
Curb's whole premise is a buyer standing on a dealer lot. The report flow needs to be fast and legible
on a phone: a lookup that works one-handed (VIN scan / plate entry), the headline numbers above the
fold, and the full breakdown a tap away. Audit the report views for small screens and tighten the
vehicle-lookup path (`vehicle_lookups_controller.rb`, `reports_controller.rb`).

### 6. Wider US "per car sold" coverage
Complaint normalization currently covers the ~220 highest-complaint models, loaded from Wikipedia sales
pages (`bin/rails curb:sales`). Models without sales fall back to share-based comparisons. Widen
coverage so more cars get a real per-car-sold rate, add a more reliable sales source than Wikipedia
scraping, and reduce the share-based fallback.

### 7. Netherlands (APK/RDW) profile parity
Dutch plates and defects already load via RDW with no API key, but `ModelProfile` weak spots are built
from UK (`model_part_profiles`) and US records. Extend the profile and rate tables so Dutch inspection
data produces the same "known weak spots" that UK cars get, giving NL users first-class reports.

### 8. Public shared reports
`shared_reports_controller.rb` scaffolds report sharing. Finish it: stable share links, an
open-graph-friendly public view, and a clear boundary on what a shared report exposes (no account data,
demo-vs-real banner preserved). Low cost, and it doubles as the product's main organic growth channel.
