# Curb

Know what a used car really costs before you sign. On the dealer lot, a buyer enters a VIN (US), a plate
(UK, Netherlands) or a make and model, plus the price, mileage and how long they'll keep it. Curb shows:

- **Likely problems**, ranked by chance and cost, for each year of ownership
- **Out-of-pocket odds**: what factory warranty, a CPO or extended plan would cover, and what they'd pay
- **Maintenance** due during ownership, with the cost of each service
- **True cost to own** = price + expected repairs + maintenance
- **Budget check**: running cost against a monthly budget, and the chance of one bill bigger than their savings
- **Negotiation notes**: recalls (US) and the car's own inspection history (UK MOT, Dutch APK)

Every figure is an estimate from inspection data, labeled with a confidence level.

## Stack

Rails 8 · Postgres · Hotwire (Turbo + Stimulus) · Solid Queue · built-in email/password authentication.
Ruby 3.4.3 (3.2.6 also passes).

## Setup

```bash
bundle install
bin/rails db:setup   # schema, reference data, demo inspections, a development sign-in
bin/dev
```

`db:setup` generates about 125,000 **synthetic** MOT inspections so the app works immediately. Reports built
on them carry a "Demo data" banner. The development sign-in is in `db/seeds.rb`.

## Loading real data

From the [DVSA dataset page](https://www.data.gov.uk/dataset/c63fca52-ae4c-4b75-bab5-8b4735e1a4c9/anonymised-mot-tests-and-results),
download and unzip into one folder (it's git-ignored if its name starts with "MOT Testing data"):

| File | Why it's needed |
|---|---|
| MOT testing data **results** (e.g. 2024) | Which car each test was on: make, model, engine, mileage, age |
| MOT testing data **failure item** (same year) | What each test found |
| MOT testing data **lookup tables** | The wording of each defect (`item_detail`), used to sort it into a category |

Failure items only count once their tests are loaded, so all three are needed. Then:

```bash
bin/rails 'curb:import:mot_dir[MOT Testing data (2024)]'   # clears demo data, loads every file it finds
bin/rails curb:categorize                                   # sorts defect wording, then rebuilds the rate tables
```

Files are matched by name (`test_result`, `test_item`, `item_detail`), read by their header row (old
pipe-separated and 2023+ comma-separated layouts both work) and loaded one at a time. Each loaded file is
recorded in `import_runs`, so re-running skips it. A year of files is several GB: expect the load to take a
while and the database to grow by a similar amount.

`curb:categorize` uses Claude when `ANTHROPIC_API_KEY` is set (model: `CURB_CATEGORIZER_MODEL`, default
`claude-opus-5`) and keyword matching otherwise. Each phrase is categorized once and reused.

## US owner complaints and service bulletins

US reports get a "What other owners say" section from two free NHTSA files
([datasets page](https://www.nhtsa.gov/nhtsa-datasets-and-apis)): `FLAT_CMPL.zip` (owner complaints) and the
`MFR_COMMS_RECEIVED_*.zip` files (bulletins makers send dealers). Unzip them into a folder, then:

```bash
bin/rails 'curb:import:nhtsa[NHTSA data]'   # about 12 minutes; replaces the previous load
```

To compare complaints **per car sold** (so popular cars aren't punished for being popular), load yearly
US sales from Wikipedia model pages (CC BY-SA; each figure keeps its source page):

```bash
bin/rails 'curb:sales[220]'   # the 220 models with the most complaints; slow on purpose (Wikipedia rate limits)
```

Pages that search can't find, or that are named differently from the model, go in `db/seeds/sales_pages.yml`.
Heavy-duty pickups are compared as families with their light-duty versions (`ModelSale::FAMILIES`),
because makers report them together. Models without sales fall back to share-based comparisons.

Complaints are stored only as counts per make, model, year and part. Names, cities, dealer details and
complaint stories in the file are never read into the database. There's no count of how many of each car
are on US roads, so complaints never become a "1 in X" chance: `OwnerReports` flags a part only when it
takes far more than its usual share of a car's complaints, far more than the model's other years, or more
than 99 in 100 cars of similar years (when it's also over-represented). Cars NHTSA files by trim
("C300", "328I") are added up per family.

## Model weak-spot profiles

`ModelProfile` pieces together what tends to go wrong on any make, model and year from three kinds of
record, and reports show the top four as "Known weak spots" (the full profile is at `/models`):

- **UK safety checks**: `model_part_profiles` (a materialized view) compares how often inspections record
  each part (fail or advisory) with an average car the same age, by engine and first-registration year.
- **US owner reports**: parts owners complain about far more than usual (`OwnerReports`).
- **Maker fixes**: service bulletins tagged with about 40 failure themes (`BulletinTheme`), flagged when a
  theme's share of the maker's fixes for the car is 2.5x or more its share for all cars that year.

A part backed by more than one kind of record is a "strong sign". Profiles say where a model tends to
have trouble, not the chance that a given car will. `bin/rails curb:refresh_rates` rebuilds the view;
`bin/rails curb:tag_bulletins` re-tags bulletins after changing the theme list.

## Configuration

| Setting | For |
|---|---|
| `ANTHROPIC_API_KEY` | Defect categorizing with Claude (optional; keywords otherwise) |
| `MOT_CLIENT_ID`, `MOT_CLIENT_SECRET`, `MOT_API_KEY`, `MOT_TENANT_ID` | UK plate lookup via the [MOT History API](https://documentation.history.mot.api.gov.uk/) (register first) |

NHTSA (VIN decode, recalls) and RDW (Dutch plates and defects) need no keys. Settings can also live in
Rails credentials (`anthropic_api_key`, `mot: { client_id: ... }`).

## How the numbers are made

| Piece | Where |
|---|---|
| Defect odds, smoothed toward the all-model average (k = 50) | `app/models/true_cost/defect_odds.rb` |
| Warranty cover left, by time and miles | `app/models/true_cost/coverage.rb` |
| Services due per year | `app/models/true_cost/maintenance_plan.rb` |
| True cost, break-the-bank risk, budget | `app/models/true_cost/calculator.rb` |
| Rate tables (materialized views, via Scenic) | `db/views/*.sql` |
| MOT bulk import | `app/services/importers/mot_bulk.rb` |
| Reference data: categories, warranty terms, service schedule, labor rates | `db/seeds/*.yml` |

The reference tables are starter values. Check warranty terms against manufacturer sites and replace
repair costs with CarMD or HaynesPro figures before launch.

## Roadmap

What's planned next — real reference data, confidence calibration, turning on billing, and more — is in
[`ROADMAP.md`](ROADMAP.md).

## Tests

```bash
bin/rails test
bin/rubocop
```
