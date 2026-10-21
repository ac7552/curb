# Roadmap

Planned work, roughly in the order I want to build it. None of it is built yet.

Every feature has to be usable by a 10-year-old. In practice that means one thing to do (paste a link,
take a photo, or nothing), an answer in one plain sentence, money in the buyer's own currency, and
curb's usual confidence label on anything that's an estimate.

## Groundwork

Two pieces are shared between features, so they get built once.

**Used-car prices.** Resale value (1) and the fair-price check (6) both need asking and selling prices by
model, year and mileage in each market. Picking and loading a source comes first for either feature.

**Reading warranty documents.** The warranty scan (3) needs to turn a PDF or photo into structured
terms, and the warranty verdict (4) reuses them. The maintenance-guide pipeline in
`app/services/maintenance_guides/` already does this for owner's manuals.

Features 5, 7 and 8 only use data curb already has, so they can go ahead while the price source is
sorted out.

## 1. Resale value and net cost

True cost is currently price + repairs + maintenance (`app/models/true_cost/calculator.rb`). It ignores
what the car is worth when you sell it, which is usually the biggest number. Estimate resale value at
the end of the ownership period and subtract it, so a $23,000 car worth $14,000 in four years shows as
costing about $9,000 to own. Uses the price, mileage and years-to-keep the buyer already enters.

## 2. Side-by-side comparison

People on a lot are usually choosing between two or three cars. The reports page already has a
"Compared with your other cars" bar. Extend it to a proper comparison: cost to own, chance of a big
repair bill, known weak spots and open recalls, with the cheaper car to own marked.

## 3. Warranty scan and coverage check

The buyer uploads or photographs a warranty (factory booklet, CPO certificate or extended-plan contract)
and curb says what it actually covers on this car right now, for example "engine and transmission
covered until about March 2027 or 60,000 miles, whichever comes first."

- Terms are pulled out with the maintenance-guide pipeline (`pdf_text.rb`, `claude_extractor.rb`,
  `validator.rb`) for PDFs, and Claude vision for photos.
- Time and miles left come from `coverage.rb` and `warranty_term`, which already do this for factory
  terms.
- Past mileage comes from UK MOT and Dutch APK records.
- Service history is new. Many plans are void if scheduled service was skipped, but curb has no service
  records. The buyer can photograph the service book or receipts; without them the check says it can't
  tell rather than guessing.

Each finding links to the line of the document it came from.

## 4. Should I buy the warranty?

For the extended plan offered at the desk. The report already estimates out-of-pocket cost for each
likely repair, and `coverage.rb` already handles CPO and extended plans. Compare the plan's price with
what it would likely pay out over the ownership period, after taking off anything existing cover pays
for (from 3). The answer is worth it or skip it, with the two amounts: "about $1,200 for the plan,
about $400 of likely claims."

## 5. Negotiation page

The report already says things like "ask if the recall was fixed." Collect all of it on one printable
page: the model's weak spots, open recalls, inspection history and how far the price is above fair.
Claude (`app/services/claude.rb`) writes each point as something to say to the seller, such as "this
engine often needs a timing chain around 70,000 miles, about $1,800, so take that off the price." Each
point links to its source.

## 6. Fair-price check

Curb says what a car costs to own but not whether the asking price is reasonable. Using the price data
from the groundwork, compare the price to similar cars at similar mileage and give one line: good, fair
or high, and the usual price. Runs off the car and price already entered.

## 7. Checklist for your mechanic

A one-page list to hand a mechanic before buying, filled in with the model's known weak spots from
`ModelProfile` (UK inspections, US owner complaints, maker bulletins) and any open recalls, written so a
non-mechanic can follow it. Almost all of the data already exists.

## 8. "Where it breaks" picture

A side and top drawing of the car with the model's trouble spots highlighted. Weak spots from
`model_part_profile`, `owner_reports` and `bulletin_theme` are placed on body zones (engine,
transmission, suspension, brakes, electrics, body) using the `defect_category` each fault is already
sorted into. Tapping a spot shows what goes wrong, at what mileage, and roughly what it costs. It
needs no photos, so it works as soon as a car is looked up.
