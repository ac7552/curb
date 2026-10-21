# Curb Roadmap

Curb already turns inspection data into a true cost of owning a used car. This next phase answers the
questions a buyer actually has on the lot: *What will it really cost me? Is this a good price? Is the
warranty worth it — and does it even still cover this car?*

**Design bar for every feature:** so simple a 4th–5th grader could use it. That means **one obvious
action** (paste a link, snap a photo) and **one plain-English verdict** (a ✅ / ⚠️ / ❌ and a single
sentence that says why) — never a table of numbers or a word like "depreciation" or "deductible" without
plain words around it.

In recommended build order. Nothing below is built yet; a few items note existing code they build on.

| # | Feature | Value | Effort | Builds on |
|---|---------|-------|--------|-----------|
| 1 | Depreciation & net cost | High | Medium–High | `true_cost/calculator.rb` |
| 2 | Side-by-side comparison | High | Medium | `reports_controller`, `report` |
| 3 | Warranty scan & live coverage check | High | Medium | `maintenance_guides/`, `coverage.rb` |
| 4 | "Should I buy the warranty?" verdict | High | Medium | `coverage.rb`, `defect_odds.rb` |
| 5 | Negotiation one-pager | High | Medium | `model_profile`, `recall`, `claude.rb` |
| 6 | Fair-price check | High | Medium–High | `vehicle_lookup`, `report` |
| 7 | Pre-purchase inspection checklist | Medium–High | Low–Medium | `model_profile` |

---

### 1. Depreciation & net cost
Right now true cost = price + repairs + maintenance (`app/models/true_cost/calculator.rb`). That leaves
out the biggest number of all: what the car is worth when you sell it. Add a resale-value estimate for
the end of the time the buyer plans to keep it, and show the real figure in plain words:

> *"This car will be worth about **$14,000** when you sell it, so it really costs you about **$9,000** to
> own — not the $23,000 on the windshield."*

**One action:** nothing new — it uses the price, mileage and years-to-keep the buyer already enters.
**One verdict:** the net cost, big, with the sticker price crossed out next to it.

### 2. Side-by-side comparison
A buyer on a lot is choosing *between* cars, not grading one. Let them pin two (or three) cars and see
them next to each other: net cost to own, chance of a big repair, known weak spots, and open recalls —
each row a plain ✅ / ⚠️ / ❌, with a thumbs-up on the one that's cheaper to own overall.

**One action:** tap "Compare" on a second report.
**One verdict:** "Car A is the cheaper one to own" + the few reasons why.

### 3. Warranty scan & live coverage check
Dealers wave a warranty as a selling point. Curb should read the actual paper and say what it really
covers *for this car, today*. The buyer photographs or uploads the warranty (factory booklet, CPO
certificate, or an extended-plan contract) and curb pulls out the terms, then checks them against the
car's age and mileage — and against its service history, because many plans are void if scheduled
maintenance was skipped.

> *"✅ Your engine and gearbox are covered until about **March 2027** or **60,000 miles**, whichever
> comes first."*
> *"⚠️ Careful — this plan needs a service every year, and we don't see one for 2024. That could cancel
> the engine cover."*

This reuses the maintenance-guide reading pipeline almost as-is: `app/services/maintenance_guides/`
(`pdf_text.rb`, `claude_extractor.rb`, `validator.rb`) turns the document into structured terms,
`app/models/true_cost/coverage.rb` and `warranty_term` already model "cover left by time and miles," and
MOT `inspection` records supply the mileage and service signal. Same trust rule as everywhere in curb:
every claim is tied back to the exact line in the document, and nothing is asserted that the paper
doesn't say. **One action:** snap the warranty. **One verdict:** a short covered / at-risk / lapsed list.

### 4. "Should I buy the warranty?" verdict
When a dealer offers an extended plan at the desk, curb says whether it's worth it. It already knows this
car's odds of each repair (`defect_odds.rb`) and what a plan would cover (`coverage.rb`); it weighs the
plan's price against the repairs it would likely pay for over the time the buyer keeps the car. Paired
with #3, it first **subtracts cover the car already has**, so the advice is about the real gap, not
double-counting.

> *"**Skip it.** You'd pay about **$1,200** for this plan and probably only use about **$400** of it."*

**One action:** type the plan's price (and months/miles). **One verdict:** Worth it / Skip it + the two
numbers behind it, in dollars, no jargon.

### 5. Negotiation one-pager
Turn everything curb found into things the buyer can actually *say* to pay less. A single printable,
phone-friendly page: the weak spots for this model, open recalls, inspection history, and how far the
true cost runs over a fair price — rewritten as plain talking points. Uses Claude (already wired in
`app/services/claude.rb`) to phrase them; every point links back to the data behind it.

> *"Things you can say to pay less:"*
> *"• This engine often needs a timing chain around 70,000 miles — that's about **$1,800**. Ask them to
> take that off the price."*

**One action:** tap "Help me negotiate" on a report. **One verdict:** a short list of sentences to say.

### 6. Fair-price check
Curb says what a car costs to *own*, but not whether the *asking price* is fair. Pull comparable listings
for the same car and mileage and show where this price sits — in one sentence, not a chart.

> *"This price looks **a little high**. Cars like this usually sell for about **$1,500 less**."*

Needs a source of listing prices (evaluating options is part of the work). Hooks into the existing
lookup (`vehicle_lookup`) and `report`. **One action:** none extra — it runs from the car and price
already entered. **One verdict:** Good price / Fair / High + the typical price.

### 7. Pre-purchase inspection checklist
A one-page list the buyer hands their mechanic, already filled in with *this* model's known weak spots
(from `ModelProfile` — UK safety checks, US owner reports, maker bulletins) and open recalls, in words a
non-mechanic understands. Cheap to build on data curb already has, and it carries curb's value past the
lot into the inspection bay.

**One action:** tap "Checklist for my mechanic." **One verdict:** a printable "please check these"
list, each item with a one-line reason.
