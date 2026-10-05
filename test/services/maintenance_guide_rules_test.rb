require "test_helper"

class MaintenanceGuideRulesTest < ActiveSupport::TestCase
  GUIDE = MaintenanceGuides::Guide.new(make: "Toyota", model: "Tacoma", model_year: 2019, url: "https://example.test/guide.pdf", title: "Guide")

  # A page built by hand: text placed letter by letter, as pdf-reader reports it.
  Char = Struct.new(:x, :y, :width, :font_size, :text)
  Page = Struct.new(:chars) do
    def runs(merge: false) = chars
  end
  Reader = Struct.new(:pages)

  def place(text, x, y, size: 8)
    text.chars.each_with_index.map { |char, i| Char.new(x + i * size * 0.5, y, size * 0.5, size, char) }
  end

  def stacked(text, x, from_y)
    text.chars.each_with_index.map { |char, i| Char.new(x, from_y + i * 5, 4, 8, char) }
  end

  def rows(items) = MaintenanceGuides::Validator.new(GUIDE).check("items" => items).rows

  test "picks the jobs to replace or rotate out of a mileage checklist" do
    text = <<~TEXT
      ■ Check installation of driver’s floor mat
      ❏ R eplace engine oil with 0W-20 oil;
      replace oil filter
      \u0007Replace spark plugs
      (2GR-FKS engine only)
      ■ Replace spark plugs 5
      ■ Rotate tires
      ■ \u0007 isually inspect brake linings V
      ■ Replace engine oil if 0W-20 oil was not used
      ■ Inspect the following:
      _ Rear differential oil
    TEXT

    items = MaintenanceGuides::Rules::ChecklistItems.from(text)

    assert_equal [ "Replace engine oil with 0W-20 oil; replace oil filter", "Replace spark plugs (2GR-FKS engine only)", "Replace spark plugs", "Rotate tires" ], items.map { _1["name"] }
    assert_equal [ nil, "2GR-FKS engine only", nil, nil ], items.map { _1["applies_to"] }
  end

  test "reads intervals written out in words" do
    interval = ->(text) { MaintenanceGuides::Rules::Sentences.interval(text)&.values_at("interval_miles", "interval_months", "first_due_miles") }

    assert_equal [ 40_000, nil, nil ], interval.("Replace every 64,000 km (40,000 miles).")
    assert_equal [ 7_500, 12, nil ], interval.("Replace when wrench indicator light is ON. (Max interval: 12 months or 12,000 km (7,500 miles))")
    assert_equal [ 60_000, 60, 120_000 ], interval.("Replace at first 192,000 km (120,000 miles) or 10 years; after that, every 96,000 km (60,000 miles) or 5 years.")
    assert_equal [ nil, 60, nil ], interval.("Replace brake fluid every five years.")
    assert_equal [ 40_000, nil, nil ], interval.("Every 40K miles")
    assert_equal [ nil, 24, nil ], interval.("3 years after initial registration, then every 2 years")
    assert_nil interval.("Check the brake fluid level.")
    assert_equal [ [ "replace the brake fluid", nil, 36 ] ],
                 MaintenanceGuides::Rules::Sentences.items("Independent of the Maintenance Minder information, replace the brake fluid every 3 years.", page: 1)
                   .map { _1.values_at("name", "interval_miles", "interval_months") }
  end

  test "reads an owner's manual's maintenance list, taking the interval most of its versions agree on" do
    text = <<~TEXT
      Service Intervals
      Tesla recommends the following maintenance items and intervals, as applicable to your vehicle.
       • Brake fluid health check every 4 years (replace if necessary)*.
       • Cabin air filter replacement every 2 years.
       • Rotate tires every 6,250 miles (10,000 km) or if tread depth difference is 2/32 in (1.5 mm) or greater, whichever comes first.
       • Cabin air filter replacement every 3 years.
       • Cabin air filter replacement every 2 years.
       • Replace the wiper blades if they streak.
    TEXT
    items = MaintenanceGuides::Rules::Sentences.items(text, page: 742)
    assert_equal [ [ "Brake fluid health check", "inspect" ], [ "Cabin air filter replacement", "replace" ], [ "Rotate tires", "rotate" ] ],
                 items.map { _1.values_at("name", "action") }.uniq

    agreed = MaintenanceGuides::RuleExtractor.new(vpic: nil).send(:agreed, items)
    tesla = GUIDE.with(make: "Tesla", model: "Model 3")
    result = MaintenanceGuides::Validator.new(tesla).check("items" => agreed.map { _1.merge("conditions" => "normal") }, "electric" => true)

    assert_equal "ok", result.status, "an electric car has no oil to change"
    assert_equal [ [ "Cabin air filter", nil, 24 ], [ "Tire rotation", 6_250, nil ] ], result.rows.map { _1.values_at(:name, :interval_miles, :interval_months) }
  end

  test "reads a grid of marks under mileage columns, with notes and a severe schedule" do
    normal = Page.new([
      *place("STANDARD MAINTENANCE", 40, 720),
      *place("Months", 40, 690), *place("6", 202, 690), *place("12", 240, 690), *place("18", 280, 690), *place("24", 320, 690),
      *place("×1000 miles", 40, 680), *place("7.5", 200, 680), *place("15", 240, 680), *place("22.5", 278, 680), *place("30", 320, 680),
      *place("Engine oil & filter", 40, 650), *[ 202, 242, 284, 322 ].flat_map { place("R", _1, 650) },
      *place("Cabin air filter", 40, 640), *place("R", 242, 640), *place("R", 322, 640),
      *place("Brake lines", 40, 630), *place("I", 242, 630), *place("I", 322, 630),
      *place("Tire (Rotation)", 40, 620), *place("Rotate every 12,000 km (7,500 miles).", 200, 620)
    ])
    severe = Page.new([
      *place("SCHEDULE 2 SEVERE", 40, 720),
      *place("×1000 miles", 40, 680), *place("5", 202, 680), *place("10", 240, 680), *place("15", 280, 680), *place("20", 320, 680),
      *place("Engine oil & filter", 40, 650), *[ 202, 242, 282, 322 ].flat_map { place("R", _1, 650) }
    ])
    grid = MaintenanceGuides::Rules::Grid.new(reader: Reader.new([ normal, severe ]))

    items = grid.items

    assert_equal [ 1, 2 ], grid.pages
    assert_equal [ [ "Oil and filter change", 7_500, 6 ], [ "Cabin air filter", 15_000, 12 ], [ "Tire rotation", 7_500, nil ] ],
                 rows(items).map { _1.values_at(:name, :interval_miles, :interval_months) }
    assert_equal [ "special" ], items.select { _1["page"] == 2 }.map { _1["conditions"] }.uniq
    assert_equal "inspect", items.find { _1["name"] == "Brake lines" }["action"]
  end

  test "goes by what the guide says its numbered schedules are for, and carries a grid onto the next page" do
    header = ->(y) { [ *place("miles x 1,000", 40, y), *place("7.5", 200, y), *place("15", 240, y), *place("22.5", 278, y), *place("30", 320, y) ] }
    severe = Page.new([ *place("Schedule 1", 40, 740), *header.(700), *place("Replace air cleaner filter", 40, 650), *[ 202, 242, 282, 322 ].flat_map { place("X", _1, 650) } ])
    normal = Page.new([ *place("Schedule 2", 40, 740), *header.(700), *place("Replace air cleaner filter", 40, 650), *[ 242, 322 ].flat_map { place("X", _1, 650) } ])
    carried = Page.new([ *place("Replace spark plugs", 40, 650), *place("X", 322, 650), *place("Inspect brake hoses", 40, 640),
                         *[ 202, 242, 282, 322 ].flat_map { place("X", _1, 640) }, *place("Inspect brake pads", 40, 630), *place("X", 242, 630) ])
    texts = [ "Schedule 1 miles x 1,000 Use Schedule 1 if you primarily operate your vehicle under severe conditions.", "Schedule 2 miles x 1,000", "Replace spark plugs X" ]

    items = MaintenanceGuides::Rules::Grid.new(reader: Reader.new([ severe, normal, carried ]), texts:).items

    assert_equal [ [ "Engine air filter", 15_000 ], [ "Spark plugs", 30_000 ] ], rows(items).map { _1.values_at(:name, :interval_miles) }
    assert_equal [ "special" ], items.select { _1["page"] == 1 }.map { _1["conditions"] }.uniq
  end

  test "keeps a marked line that starts in lower case as a job of its own" do
    header = [ *place("miles x 1,000", 40, 700), *place("7.5", 200, 700), *place("15", 240, 700), *place("22.5", 278, 700), *place("30", 320, 700) ]
    page = Page.new([ *header, *place("Replace spark plugs", 40, 650), *place("X", 322, 650),
                      *place("adjust valve clearance", 40, 640), *place("X", 242, 640), *place("X", 322, 640) ])

    items = MaintenanceGuides::Rules::Grid.new(reader: Reader.new([ page ])).items

    assert_equal [ [ "Spark plugs", 30_000 ] ], rows(items).map { _1.values_at(:name, :interval_miles) }
  end

  test "reads mileages stacked digit by digit above a months row, as Jeep prints them" do
    columns = [ 300, 340, 380, 420 ]
    page = Page.new([
      *columns.zip(%w[7,500 15,000 22,500 30,000]).flat_map { |x, miles| stacked(miles, x, 660) },
      *place("Or Months: 12", 220, 640), *place("24", 336, 640), *place("36", 376, 640), *place("48", 416, 640),
      *place("Change engine oil and filter.", 40, 600), *columns.flat_map { place("X", _1 - 2, 600) },
      *place("Rotate tires", 40, 590), *columns.flat_map { place("X", _1 - 2, 590) }
    ])

    items = MaintenanceGuides::Rules::Grid.new(reader: Reader.new([ page ])).items

    assert_equal [ [ "Oil and filter change", 7_500, 12 ], [ "Tire rotation", 7_500, 12 ] ], rows(items).map { _1.values_at(:name, :interval_miles, :interval_months) }
  end

  test "reads sideways mileages, shared check marks and footnotes, as GM prints them" do
    columns = [ 300, 340, 380, 420 ]
    page = Page.new([
      *columns.zip(%w[7,500mi 15,000mi 22,500mi 30,000mi]).flat_map { |x, miles| stacked(miles, x, 640) },
      *place("Rotate tires.", 40, 626),
      *place("Check engine oil level.", 40, 620), *columns.flat_map { place("@", _1 - 2, 620) },
      *place("Change engine oil and filter, if needed.", 40, 614),
      *place("Replace engine air filter. (4)", 40, 600), *place("@", 418, 600),
      *place("Replace brake fluid. (7)", 40, 590),
      *place("Replace windshield wiper blades.", 40, 580), *columns.flat_map { place("@", _1 - 2, 580) },
      *place("(4) Or every four years, whichever comes first.", 40, 560),
      *place("(7) Replace brake fluid every five years.", 320, 560)
    ])

    items = MaintenanceGuides::Rules::Grid.new(reader: Reader.new([ page ])).items

    assert_equal [ [ "Tire rotation", 7_500, nil ], [ "Oil and filter change", 7_500, nil ], [ "Engine air filter", 30_000, 48 ], [ "Brake fluid change", nil, 60 ] ],
                 rows(items).map { _1.values_at(:name, :interval_miles, :interval_months) }
  end

  test "reads service bundles and the extra jobs table, as VW and Audi file them" do
    text = <<~TEXT
                                           Service intervals in miles
                                10K     20K     30K    40K
       Minor Maintenance             X               X
       (Every 1 year)1
       Standard Maintenance                  X               X
      Minor Maintenance
       Engine Oil and Oil filter - Change oil and replace filter
       Brake system - Check the thickness of the disc brake pads
      Standard Maintenance (Includes All Minor Maintenance Items)
       Wiper blades - Check condition
                                           Additional Maintenance Items
       Work to be completed                   Interval                               Model Application
          Air filter - Replace                Every 40,000 miles                     RS7, A8 LWB only
          Air filter - Replace
                                              Every 60,000 miles                     All vehicles except RS7 and A8 LWB
          Dust and Pollen filter - Replace    Every 20,000 miles or 2 years,         All vehicles
                                              whichever occurs first
    TEXT

    items = MaintenanceGuides::Rules::Bundles.items([ text ])

    assert_equal [ [ "Engine Oil and Oil filter: Change oil and replace filter", 10_000, 12, nil ],
                   [ "Air filter - Replace", 40_000, nil, "RS7, A8 LWB only" ],
                   [ "Air filter - Replace", 60_000, nil, "All vehicles except RS7 and A8 LWB" ],
                   [ "Dust and Pollen filter - Replace", 20_000, 24, "All vehicles" ] ],
                 items.map { _1.values_at("name", "interval_miles", "interval_months", "applies_to") }
  end

  class FakeVpic
    def models(make:, model_year:) = [ "A4", "A4 allroad", "A8", "RS 7", "Outback", "WRX", "BRZ" ]
  end

  test "keeps only the jobs for this model from a booklet or filing for every model" do
    extractor = MaintenanceGuides::RuleExtractor.new(vpic: FakeVpic.new)
    item = ->(name, applies_to = nil) { { "name" => name, "applies_to" => applies_to } }
    audi = GUIDE.with(make: "Audi", model: "A4", kind: :nhtsa_filing)
    subaru = GUIDE.with(make: "Subaru", model: "Outback", kind: :all_models_booklet)

    kept = extractor.send(:for_model, [ item.("Air filter", "RS7, A8 LWB only"), item.("Air filter", "All vehicles except RS7 and A8 LWB"),
                                        item.("Spark plugs", "A3, S3, A4, S4, A4 allroad"), item.("Spark plugs", "6 Cyl: 3.6L engines only") ], audi)
    assert_equal [ [ "Air filter", nil ], [ "Spark plugs", nil ], [ "Spark plugs", "6 Cyl: 3.6L engines only" ] ], kept.map { _1.values_at("name", "applies_to") }

    kept = extractor.send(:for_model, [ item.("Timing belt (WRX STI)"), item.("Brake fluid / clutch fluid (MT only)"), item.("CVT fluid (except BRZ & Hybrid)"),
                                        item.("Engine coolant (engine side), (inverter assembly side - Hybrid)") ], subaru)
    assert_equal [ "Brake fluid / clutch fluid (MT only)", "CVT fluid (except BRZ & Hybrid)", "Engine coolant (engine side), (inverter assembly side - Hybrid)" ], kept.map { _1["name"] }
  end

  test "builds words from letters by the gaps between them" do
    chars = place("Rotate", 10, 100) + place("tires", 40, 100) + place("R", 100, 100) + [ Char.new(103, 100, 1, 8, "\t") ] + place("R", 120, 100)

    words = MaintenanceGuides::PdfText.words(chars)

    assert_equal %w[Rotate tires R R], words.map(&:text)
    assert_equal [ "Rotate tires", "R", "R" ], MaintenanceGuides::PdfText.phrases(words).map(&:text)
  end

  class FakeRules
    def initialize(extraction) = @extraction = extraction
    def extract(*, **) = @extraction
  end

  class FakeModel
    def initialize(&block) = @block = block
    def extract(*, **) = @block.call
  end

  def oil(miles) = { "name" => "Replace engine oil and oil filter", "action" => "replace", "interval_miles" => miles, "interval_months" => 12,
                     "first_due_miles" => nil, "conditions" => "normal", "applies_to" => nil, "page" => 1 }

  # A reader with the download and the PDF left out.
  class OfflineReader < MaintenanceGuides::Reader
    private
      def download(_guide) = "guide.pdf"
      def schedule_pages(_pdf) = [ MaintenanceGuides::PdfText::Page.new(number: 3, columns: [ "text" ]) ]
  end

  def read_with(rules:, model:)
    OfflineReader.new(rules: FakeRules.new(rules), extractor: model).read(GUIDE)
  end

  test "reads with rules first, and asks the model only when the rules can't give a clean reading" do
    asked = 0
    model = FakeModel.new { asked += 1; { "items" => [ oil(10_000) ], "model" => "claude" } }

    clean = read_with(rules: { "items" => [ oil(10_000) ], "model" => "rules", "pages" => [ 39 ] }, model:)
    assert_equal [ "ok", "rules", 0 ], [ clean.result.status, clean.extraction["model"], asked ]

    doubtful = read_with(rules: { "items" => [ oil(500) ], "model" => "rules", "pages" => [ 39 ] }, model:)
    assert_equal [ "ok", "claude", 1, [ 3 ] ], [ doubtful.result.status, doubtful.extraction["model"], asked, doubtful.pages ]

    no_model = read_with(rules: { "items" => [ oil(500) ], "model" => "rules", "pages" => [ 39 ] }, model: nil)
    assert_equal [ "needs_review", "rules" ], [ no_model.result.status, no_model.extraction["model"] ]

    error = assert_raises(MaintenanceGuides::Reader::Error) { read_with(rules: nil, model: nil) }
    assert_match "no Claude API key", error.message
  end
end
