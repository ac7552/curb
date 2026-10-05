# Plan: maintenance schedules from the makers' own guides

**Status:** in progress · **Owner:** Aaron · **Updated:** 2026-10-03

## Why

Every car gets the same upkeep today: one generic schedule in `db/seeds/service_items.yml`. A Tacoma, a
CR-V and a Model 3 get the same oil changes and transmission fluid, and the report can only cite them as
"Curb's estimates". Makers publish their real schedules for free. This plan pulls them in for the cars
people actually check, cites the guide and page, and keeps the generic schedule as the fallback.

## What already works

| Piece | Where | State |
|---|---|---|
| Toyota guide finder | `app/services/maintenance_guides/finder.rb` | Done |
| Schedule pages out of a PDF, column by column | `pdf_text.rb` | Done |
| One checklist per mileage, special conditions and conditional notes removed | `checklists.rb` | Done (Toyota layout) |
| Local Gemma 4 12B reads one checklist at a time | `local_extractor.rb`, `bin/guide-model` | Done, free, about 2 min a guide |
| Intervals worked out from where items appear | `intervals.rb` | Done |
| Sanity checks, "needs review" | `validator.rb` | Done |
| Batch over best sellers 2016 onward, resumable, failures logged | `prefill.rb`, `bin/rails curb:guides:prefill` | Built, not run yet, no tests |
| Results table and seed files | `maintenance_guides` table, `db/seeds/maintenance_guides/` | Done |
| Accuracy | 2019 Tacoma and 2020 Camry | 7 of 7 items correct on each |

**Not done:** reports don't use the results yet; only Toyota has a finder.

## How it fits together

```
 Car (year, make, model)
   │
   ▼
 1. SOURCE     where the maker publishes the schedule (one class per maker, see the table below)
   │            → a PDF address, or a fixed rule (Mercedes)
   ▼
 2. READER     download → schedule pages → LAYOUT splits into checklists → Gemma reads each one
   │            → Intervals works out how often → Validator checks it
   ▼
 3. STORE      db/seeds/maintenance_guides/<make>/<year>-<model>.json  (committed, loaded by db:seed)
   │            status: ok | needs_review
   ▼
 4. REPORT     calculator uses the guide's intervals for that car (ok only), cites guide + page,
                and falls back to the generic schedule for anything the guide doesn't cover
```

Steps 1–3 run on a developer's Mac (free). Step 4 is the live app, which only reads the stored results.

## Step 1: sources, maker by maker

Researched 2026-10-03. "Tested" means real requests for several years and models.

### Ready: address pattern or lookup service, no login

| Maker | Kind | How | Tested |
|---|---|---|---|
| Toyota | Address | `assets.sia.toyota.com/publications/en/omms-s/T-MMS-{yy}{Model}/pdf/T-MMS-{yy}{Model}.pdf` | Working |
| Lexus | Address | Same server, `L-MMS-{yy}{Model}`. Newer guides combine models (`ES250ES350`), so the source needs a small name table. | 5 of 5 |
| Nissan | Address | `www.nissanusa.com/content/dam/Nissan/us/manuals-and-guides/{model}/{year}/{year}-nissan-{model}-owner-manual.pdf` | 5 of 5 |
| Infiniti | Address | `www.infinitiusa.com/content/dam/Infiniti/US/manuals_guides/{model}/{year}/{year}-infiniti-{model}-owner-manual.pdf` | 4 of 5 (Q50 needs another name) |
| Chevrolet, GMC, Buick, Cadillac | Lookup service | GET `contentdelivery.ext.gm.com/bypass/gma-search-api/searchapi/solr/gma-public/select?{query}`, where the query is the site's own search string for `+{YEAR} +{MAKE} +{MODEL}`, filtered to manual PDFs. Returns owner manual and warranty book links. | 4 of 4, 2016–2022 |
| Hyundai | Lookup service | POST `owners.hyundaiusa.com/bin/common/resourceResult` with `resultType=manualandwarranties`, `tags={YEAR} HYUNDAI {MODEL}` (a cookie session from the manuals page first). Returns that car's owner manual and the year's warranty handbook. | 3 of 3 |

### Ready with name variations: the source tries a short list of candidate addresses

| Maker | How | Notes |
|---|---|---|
| Honda | `owners.honda.com/utility/download?path=/static/pdfs/{year}/{Model}/{year}_{Model}_Maintenance_Minder[_System].pdf` | Civic and Accord need body-style folders and codes (`Civic Sedan`, `4D`); the extension may be `.PDF` |
| Acura | Same, on `owners.acura.com` | Both file names occur |
| Mazda | `www.mazdausa.com/siteassets/pdf/owners-optimized/{year}/{folder}/{year}-{name}-scheduled-maintenance.pdf` | Folders vary (`mazda3-4door`, `m3h`), and so do file names (`schedule` vs `scheduled`, `_` vs `-`) |

### A short hand-made address file: one document covers many models

`db/seeds/guide_addresses.yml`, typed once and checked into the repo:

| Maker | What to list | About how many |
|---|---|---|
| BMW, MINI | Yearly "Maintenance" booklet, all models (e.g. `bmwusa.com/content/dam/bmw/marketUS/common/warranty-books/2025/BMW_MY25_Maintenance_with_BEVs.pdf`) | 11 + 11 |
| Porsche | Yearly US warranty and maintenance manual (`files.porsche.com/f/332100/{code}/{year}-us-warranty-manual.pdf`) | 11 |
| Subaru | Yearly warranty and maintenance booklet (`techinfo.subaru.com/stis/doc/warrantyBooklet/...`) | 11 |
| Volvo | Factory maintenance sheets, each covering a range of years | 4–5 |
| VW, Audi | Per-model schedules filed with NHTSA. Already in `service_bulletins` (VW: 119 documents, Audi: 24); the file is `static.nhtsa.gov/odi/tsbs/{year}/MC-{document_id}-{part}.pdf`. The part number needs confirming per document. | from data |

### A fixed rule: no document to read

| Maker | Rule |
|---|---|
| Mercedes-Benz | Service A (oil and filter, checks) every 10,000 mi or 1 year, alternating with Service B (adds cabin filter and brake fluid). Entered once as make rows in `service_items.yml`. Model-specific items (spark plugs and so on) stay generic. |
| Tesla | The short intervals page on tesla.com, entered once |

### Blocked: no automated route

| Maker | Why | Options |
|---|---|---|
| Ford, Lincoln | Per-car page (`ford.com/support/owner-manuals-details/{model}/{year}`) and the PDFs both refuse programs (bot protection) | Ask Ford for data access; or a person saves the PDFs for top models into `tmp/guides/`, and the batch reads local files |
| Kia | US search is behind a CAPTCHA; the old Kia Canada files are gone | Check Kia UK and EU sites; or a hand-collected address list |
| Jeep, Ram, Dodge, Chrysler, Alfa Romeo, Maserati | PDFs are public (`msmownerassets.z13.web.core.windows.net/assets/publications/en-us/{Brand}/{year}/{Model}/{id}.pdf`), but the number `{id}` comes from a lookup that needs a Mopar login | A hand-collected list of `{id}`s for top models (web search finds many); or ask Stellantis |
| Genesis | Own site refuses programs; Hyundai's service returned nothing for Genesis models | Retry through Hyundai's service with a browser-style session; else a hand list |
| Land Rover, Jaguar | Not researched yet | — |

Never get around a CAPTCHA, login or bot block. Those makers stay on the generic schedule until one of
the options above works.

### Code shape

```ruby
# app/services/maintenance_guides/sources/*.rb — one per kind, configured per maker
Sources::AddressPattern   # Toyota, Lexus, Nissan, Infiniti, Honda, Acura, Mazda — candidate URLs, first that's a PDF wins
Sources::GmSearch         # Chevrolet, GMC, Buick, Cadillac
Sources::HyundaiLookup    # Hyundai (and Genesis if it works)
Sources::AddressFile      # BMW, MINI, Porsche, Subaru, Volvo — reads db/seeds/guide_addresses.yml
Sources::NhtsaFiling      # VW, Audi — from service_bulletins
Sources.for(make)         # registry; replaces Finder::SUPPORTED_MAKES
```

Each source returns `Guide(url:, title:, kind:)`. `kind` tells the reader what it's looking at:
`:maintenance_guide` (Toyota, Lexus, Mazda, Honda), `:owner_manual` (Nissan, Infiniti, GM, Hyundai —
400–600 pages, the schedule is one chapter), or `:all_models_booklet` (BMW, Porsche, Subaru, Volvo —
the reader must pick out this model's section).

## Step 2: reading different layouts

`Checklists` today understands Toyota's layout: a checklist per mileage heading. Other makers print
schedules differently, so splitting becomes one small `Layout` class per family, chosen by the source:

| Layout | Looks like | Makers (to confirm with each maker's answer key) |
|---|---|---|
| `MileageChecklists` (today's `Checklists`) | "30,000 miles or 36 months" followed by a list | Toyota, Lexus |
| `ItemIntervals` | One row per item with its interval in words ("Replace every 30,000 miles or 24 months") | likely Nissan, Infiniti, Hyundai, Mazda, Subaru |
| `IntervalGrid` | Items down the side, mileages across the top, ✓ or X marks | likely GM, BMW, Volvo |
| `MinderCodes` | Codes (A, B, 1–7) explaining what each service includes, no fixed miles | Honda, Acura, and GM's oil-life monitor. Use the guide's items with typical intervals, labeled as such |

The rest of the reader is shared: finding schedule pages, the local model reading one small piece at a
time, `Intervals`, and `Validator`. In an owner's manual, page finding starts from the table of contents
or a "Maintenance schedule" heading, not the whole PDF.

## Step 3: trust before anything is used

- **Answer keys per maker.** For each maker, type in the real schedule for 3 guides (different years and
  models) as `test/fixtures/guide_answer_keys/<make>/<year>-<model>.yml`. A test reads those guides with
  the cached model answers and must match every replace-item interval.
- **Publish gate.** The batch marks a maker's results `ok` only when that maker's answer keys pass;
  otherwise everything is `needs_review`. Only `ok` rows reach reports.
- **Spot checks.** After each batch, look at 5 random `ok` results against their PDFs.

## Step 4: using the results in reports

1. `ServiceItem.schedule_for` takes the car's year too, and uses an `ok` `MaintenanceGuide` when there is
   one. Each guide row becomes a schedule item: interval and first-due from the guide, labor and parts
   price from the generic row of the same name (prices stay Curb's estimates).
2. Items the guide doesn't mention (wipers, battery, tires as wear items) still come from the generic schedule.
3. Year by year cites the guide: "Toyota 2019 Tacoma Warranty & Maintenance Guide, p. 41 ↗". The Sources
   section lists it. Cars without a guide say so: "Typical schedule — we don't have Ford's guide for this car."
4. Tests: a car with a guide gets the guide's intervals and citation; one without keeps today's behaviour.

## Running it

```bash
bin/guide-model                                   # tab 1: the local model
caffeinate -i bin/rails curb:guides:prefill MAKES=Toyota,Lexus,Nissan,Chevrolet   # tab 2
bin/rails curb:guides:failures                    # what to retry or look at by hand
```

Commit `db/seeds/maintenance_guides/`. Production picks the results up on the next deploy's `db:seed`.

**Pace:** about 2 minutes per guide, longer for 500-page owner's manuals. The top 12 models of 10 makers
from 2016 on is roughly 1,200 guides, about 2–3 days of Mac time spread over several runs. Start with the
best sellers.

## Being a good guest

- One request at a time per site, a pause between requests, and a User-Agent with a contact address.
- Store only the intervals and a link to the guide, never the PDF. Downloads stay in git-ignored `tmp/guides/`.
- The GM and Hyundai lookups are services their websites use, not published developer tools. Read each
  maker's site terms before turning its source on, and expect them to change: the batch logs failures,
  so a change shows up as a run of "no guide found".
- Get a quick legal check before launch.

## Order of work

| # | Work | Done when |
|---|---|---|
| 1 | Tests for the batch (`Prefill`); remove the leftover `ERROR_LOG` constant | Suite covers save, skip, failure log, server-down stop |
| 2 | Run the Toyota batch | Toyota best sellers 2016+ in `db/seeds/maintenance_guides/toyota/` |
| 3 | **Use the results in reports** (step 4) | A Toyota check shows the guide's schedule and citation |
| 4 | `Sources` registry; Lexus | Lexus answer keys pass; batch run |
| 5 | Nissan, Infiniti: `ItemIntervals` layout, owner-manual page finding | Answer keys pass; batch run |
| 6 | GM search; GM layout | Answer keys pass for Chevrolet and GMC; batch run |
| 7 | Hyundai lookup | Answer keys pass; batch run |
| 8 | Honda, Acura (`MinderCodes`), Mazda | Answer keys pass; batch run |
| 9 | Address file for BMW, MINI, Porsche, Subaru, Volvo; NHTSA filings for VW, Audi; Mercedes and Tesla rules | Each maker's answer keys pass |
| 10 | Blocked makers: ask Ford and Stellantis; check Kia UK/EU; retry Genesis | Decision per maker |
| 11 | "Look up maintenance schedule" button and finish badge for cars not prefilled | Needs a production reader (Claude API or a free-tier service); decide after 1–9 show how much is left |

## Open questions

1. Which makers to prefill first after Toyota? Suggest by sales: Chevrolet, Nissan, Hyundai, Honda.
2. Ask Ford and Stellantis for data access now? Those two cover several of the top US sellers.
3. Is a person saving Ford PDFs by hand for the top models acceptable as a stopgap?
