# Curb Roadmap

Curb already turns inspection data into a true cost of ownership. The next phase makes it the tool a
buyer actually pulls out on the lot: it should tell you what the car will *net* cost, whether this one
is a good deal, what to say to knock the price down, and whether the warranty is worth it — all from
data no listing site puts together.

Grouped by theme and in rough build order. Statuses are honest: the headline features below are not
built yet; a few items note existing scaffolding they build on.

## A. Complete the "true cost" promise

| # | Feature | Value | Effort | Status |
|---|---------|-------|--------|--------|
| 1 | Depreciation & resale forecast → real *net* cost | High | Medium–High | Planned |
| 2 | Side-by-side car comparison | High | Medium | Planned |
| 3 | "Should I buy the warranty?" expected-value engine | High | Medium | Builds on `coverage.rb` |
| 4 | Fuel / energy & EV battery-degradation modeling | Medium–High | Medium | Planned |

## B. The on-the-lot superpowers

| # | Feature | Value | Effort | Status |
|---|---------|-------|--------|--------|
| 5 | Negotiation one-pager (data → leverage) | High | Medium | Planned |
| 6 | Photo condition scan from the lot | High | High | Reuses garage photo infra |
| 7 | Fair-price check vs. the market | High | Medium–High | Planned |
| 8 | Tailored pre-purchase inspection checklist | Medium | Low–Medium | Builds on `ModelProfile` |

## C. Reach & growth

| # | Feature | Value | Effort | Status |
|---|---------|-------|--------|--------|
| 9 | Watchlist + recall / bulletin alerts | Medium–High | Medium | Planned |
| 10 | Public shared reports + embeddable "true cost" badge | Medium | Medium | `shared_reports` scaffolded |
| 11 | New regions: Germany (TÜV), then France | Medium | High | Planned |

## D. Foundations (make every number defensible)

| # | Feature | Value | Effort | Status |
|---|---------|-------|--------|--------|
| 12 | Real reference data (CarMD/HaynesPro costs, verified warranties) | High | Medium | Planned |
| 13 | Confidence calibration + accuracy back-test harness | High | Medium–High | Planned |
| 14 | Turn on billing | High | Medium | Built, switched off |

---

### 1. Depreciation & resale forecast → real *net* cost
Today true cost = price + repairs + maintenance (`app/models/true_cost/calculator.rb`). That ignores the
single biggest line item: how much the car is worth when you sell it. Model resale value at the end of
the holding period (by make/model/age/mileage, with region-specific curves) and report **net cost =
price − resale + repairs + maintenance**. Add a cost-per-year curve that surfaces the cheapest window
to buy and to sell. This closes the biggest gap in the headline number and makes every other figure
more honest.

### 2. Side-by-side car comparison
A buyer on a lot is choosing *between* cars, not evaluating one in isolation. Let them pin two or three
reports and compare net cost, break-the-bank risk, known weak spots, recalls and confidence in one
view. Turns a single verdict into a decision tool — and is the feature most likely to get shared.

### 3. "Should I buy the warranty?" expected-value engine
Curb already computes what a factory/CPO/extended plan would cover (`coverage.rb`) and each part's
defect odds (`defect_odds.rb`). Combine them into an explicit expected-value verdict: given *this* car's
odds, *this* plan's price and terms, and *your* holding period, is the plan +EV or −EV, and by how
much? Show the distribution, not just a point estimate. Dealers sell these plans at the desk — a
data-backed "worth it / skip it" is a genuine superpower.

### 4. Fuel / energy & EV battery-degradation modeling
Running cost is a top-three expense and isn't modeled yet. Add fuel/electricity cost from the car's
economy and the buyer's annual mileage. For EVs, use inspection and complaint data to estimate battery
degradation risk and fold expected range loss (and replacement odds) into the true cost — something
almost no used-car tool does well.

### 5. Negotiation one-pager (data → leverage)
Translate the report into leverage the buyer can act on: a printable, phone-friendly one-pager that
turns weak spots, open recalls, MOT/APK history and the true-cost delta into specific talking points
("this engine family fails on timing chains around 70k — budget ~$1,800 — ask for $X off"). Use Claude
(already wired for defect categorizing) to phrase it; every claim links back to the data behind it.

### 6. Photo condition scan from the lot
Curb already stores walk-around photos and places accessories on them (`garage_photos_controller.rb`,
`accessory_placements_controller.rb`). Reuse that pipeline so a buyer snaps the dash, tires, panel gaps
and odometer on the lot and Claude vision flags dashboard warning lights, tire wear, mismatched panels
or an odometer that doesn't fit the car's MOT mileage history — then folds the findings into the
estimate's confidence. The most "standing in front of the car" feature on the list.

### 7. Fair-price check vs. the market
Curb says what a car will cost to *own* but not whether the *asking price* is fair. Pull comparable
listings for the same spec and mileage band, show where this price sits in the distribution, and flag
over/under-priced. Combined with net cost, this is the "is this a good deal?" answer buyers actually
come for. (Needs a listings data source — evaluate options as part of the work.)

### 8. Tailored pre-purchase inspection checklist
Generate a one-page PPI checklist the buyer hands their mechanic, pre-loaded with this exact model's
known weak spots from `ModelProfile` (UK safety checks, US owner reports, maker bulletins) plus the
open recalls. Cheap to build on data that already exists, and it extends curb's value past the lot into
the inspection bay.

### 9. Watchlist + recall / bulletin alerts
Let a signed-in user follow a specific car (in their garage) or a model they're shopping, and get
notified when a new recall or service bulletin lands, or when the weak-spot profile shifts. Turns a
one-shot report into a reason to come back, and leans on data curb already imports.

### 10. Public shared reports + embeddable "true cost" badge
Finish report sharing (`shared_reports_controller.rb`): stable links, an open-graph public view, and a
clear boundary on what's exposed (no account data, demo-vs-real banner kept). Then offer an embeddable
"true cost to own" badge that listing sites, forums and sellers can drop onto a listing — curb's main
organic-growth and B2B wedge in one.

### 11. New regions: Germany (TÜV), then France
Curb's architecture already spans three countries' inspection regimes (UK MOT, Dutch APK/RDW, US). The
data layer is the hard part and it's proven; adding Germany's TÜV data and then France extends the
model to large markets without reinventing the engine.

### 12. Real reference data
The warranty terms, service schedule and labor/repair costs in `db/seeds/*.yml` are starter values (the
README says so). Replace repair costs with CarMD or HaynesPro figures, verify each warranty term against
the manufacturer, and check the service schedule, so reports can drop the "demo" caveat. Underpins #1,
#3 and #5.

### 13. Confidence calibration + accuracy back-test harness
Every figure is labeled with a confidence level that isn't yet validated. Build a harness that
back-tests `defect_odds.rb` and `calculator.rb` against held-out MOT years, then set the smoothing
constant (k = 50 today) and the confidence bands from measured error instead of by hand.

### 14. Turn on billing
Plans, payments, check limits and Stripe webhooks are built behind a feature switch
(`plans_controller.rb`, `subscriptions_controller.rb`, `stripe_webhooks_controller.rb`;
[`docs/billing.md`](docs/billing.md)) and off for now. Finalize tiers and the free limit, move Stripe to
live keys, exercise subscribe → webhook → entitlement end to end, add dunning/cancellation, then flip it
on.
