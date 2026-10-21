# Curb Roadmap

Curb already turns inspection data into the true cost of owning a used car. The next phase answers the
questions a buyer actually has on the lot: *What will it really cost me? Is this a good price? Is the
warranty worth it, and does it even still cover this car?*

## Design bar

Every feature has to be simple enough for a 4th or 5th grader:

- **One obvious action**: paste a link, snap a photo, or nothing at all.
- **One plain verdict**: a ✅ / ⚠️ / ❌ and one sentence that says why. No tables to read, and no words
  like "depreciation" or "deductible" without plain words around them.
- **Honest about certainty**: every verdict keeps curb's confidence label, said plainly ("we're pretty
  sure" / "rough guess").
- **The buyer's money**: amounts in their own currency ($, £ or €) and distance unit.

## The features

In priority order. Nothing below is built yet; each item names the existing code it builds on.

| # | Feature | Value | Effort | Builds on |
|---|---------|-------|--------|-----------|
| 1 | Resale value & net cost | High | Medium–High | `true_cost/calculator.rb` |
| 2 | Side-by-side comparison | High | Medium | Reports page comparison bar |
| 3 | Warranty scan & coverage check | High | Medium–High | `maintenance_guides/`, `coverage.rb` |
| 4 | "Should I buy the warranty?" | High | Medium | `coverage.rb`, `calculator.rb` |
| 5 | Negotiation one-pager | High | Medium | Report recall notes, `model_profile`, `claude.rb` |
| 6 | Fair-price check | High | Medium–High | `vehicle_lookup`, `report` |
| 7 | Checklist for your mechanic | Medium–High | Low–Medium | `model_profile` |
| 8 | "Where it breaks" picture | High | Medium | `model_part_profile`, `defect_category` |

### Shared groundwork

Two pieces of new plumbing serve more than one feature, so each gets built once:

- **Used-car price data** (#1 and #6). Resale value and fair price both need real asking and selling
  prices by model, year and mileage in each market. Choosing and loading that source is the first job
  for either feature.
- **Document reading** (#3, reused by #4). Turning a warranty PDF or photo into structured terms. The
  maintenance-guide pipeline already does this for owner's manuals.

Features 5, 7 and 8 run entirely on data curb already has, so they can ship while the price source is
being sorted out.

---

### 1. Resale value & net cost
Today true cost = price + repairs + maintenance (`app/models/true_cost/calculator.rb`). That leaves out
the biggest number of all: what the car is worth when you sell it. Estimate resale value at the end of
the time the buyer plans to keep it, and subtract it.

> *"This car will be worth about **$14,000** when you sell it, so it really costs you about **$9,000** to
> own, not the $23,000 on the windshield."*

**Action:** none. It uses the price, mileage and years-to-keep the buyer already enters.
**Verdict:** the net cost, big, with the sticker price crossed out beside it.

### 2. Side-by-side comparison
A buyer on a lot is choosing *between* cars. The reports page already has a "Compared with your other
cars" bar; grow that into a real side-by-side of two or three cars: net cost to own, chance of a big
repair bill, known weak spots and open recalls. Each row is a ✅ / ⚠️ / ❌, with a thumbs-up on the car
that's cheaper to own.

**Action:** tap "Compare" on a second report.
**Verdict:** "Car A is cheaper to own," plus the two or three reasons why.

### 3. Warranty scan & coverage check
Dealers sell a warranty as a reason to buy. Curb reads the actual paper and says what it covers *for this
car, today*. The buyer uploads or photographs the warranty (factory booklet, CPO certificate or
extended-plan contract). Curb pulls out the terms and checks them against the car's age, its mileage, and
its service history, because many plans are void if scheduled service was skipped.

> *"✅ Your engine and transmission are covered until about **March 2027** or **60,000 miles**,
> whichever comes first."*
> *"⚠️ Careful: this plan needs a service every year, and there's no record of one for 2024. That could
> cancel the engine cover."*

How it's built:
- **Reading the paper:** the maintenance-guide pipeline in `app/services/maintenance_guides/`
  (`pdf_text.rb`, `claude_extractor.rb`, `validator.rb`) handles PDFs; photos are read with Claude vision.
- **Time and miles left:** `app/models/true_cost/coverage.rb` and `warranty_term` already work this out.
- **Mileage history:** UK MOT and Dutch APK records give past odometer readings.
- **Service history (new):** curb has no service records yet. The buyer adds them the easy way: snap the
  service book or receipts. Without them, the verdict says "we can't tell" instead of guessing.

Same trust rule as the rest of curb: every claim points to the line in the document it came from, and
nothing is said that the paper doesn't say.

**Action:** snap the warranty.
**Verdict:** a short list of what's covered, at risk, or run out.

### 4. "Should I buy the warranty?"
When a dealer offers an extended plan at the desk, curb says whether it's worth the money. The report
already works out what the buyer would pay out of pocket for each likely repair, and `coverage.rb`
already handles CPO and extended plans. This compares the plan's price with the repair bills it would
actually pay over the time the buyer keeps the car. With #3, it first takes off what the car's existing
cover already pays for, so nothing is counted twice.

> *"**Skip it.** You'd pay about **$1,200** for this plan and probably only use about **$400** of it."*

**Action:** type the plan's price and how long it lasts.
**Verdict:** Worth it / Skip it, plus the two amounts behind it.

### 5. Negotiation one-pager
Turn what curb found into things the buyer can *say* to pay less. The report already prompts "ask if the
recall was fixed"; this gathers every point into one printable, phone-friendly page: the model's weak
spots, open recalls, inspection history, and how far the price sits above fair. Claude
(`app/services/claude.rb`) writes the sentences; each one links to the data behind it.

> *"Things you can say to pay less:*
> *• This engine often needs a timing chain around 70,000 miles. That's about **$1,800**. Ask them to
> take it off the price."*

**Action:** tap "Help me negotiate" on a report.
**Verdict:** a short list of sentences to say.

### 6. Fair-price check
Curb says what a car costs to *own*, but not whether the *asking price* is fair. Using the price data
from the shared groundwork, find cars like this one at similar mileage and say where this price sits,
in one sentence rather than a chart.

> *"This price looks **a little high**. Cars like this usually sell for about **$1,500 less**."*

**Action:** none. It runs from the car and price already entered.
**Verdict:** Good price / Fair / High, plus the usual price.

### 7. Checklist for your mechanic
A one-page list the buyer hands their mechanic before buying, already filled in with *this* model's known
weak spots (from `ModelProfile`: UK safety checks, US owner reports and maker bulletins) and any open
recalls, in words a non-mechanic understands. Cheap to build on data curb already has, and it carries
curb's help past the lot into the repair shop.

**Action:** tap "Checklist for my mechanic."
**Verdict:** a printable "please check these" list, each item with a one-line reason.

### 8. "Where it breaks" picture
A simple drawing of the car, side and top view, with its trouble spots lit up for that exact model. No
photo needed: it's drawn from data curb already has (`model_part_profile`, `owner_reports`,
`bulletin_theme`), placed on body zones (engine, transmission, suspension, brakes, electrics, body)
through the `defect_category` every fault is already sorted into. Tap a glowing spot to see what goes
wrong, when, and what it costs:

> *"Timing chain: tends to go around **70,000 miles**. Costs about **$1,800**. Ask your mechanic to
> check it."*

Because it's drawn from data, it works the moment a car is looked up and looks the same for every model.
It turns "known weak spots" from a list into something a kid can read at a glance.

**Action:** look up a car.
**Verdict:** a picture of the car with its weak spots glowing, and one plain sentence on each.
