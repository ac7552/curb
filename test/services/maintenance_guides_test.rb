require "test_helper"

class MaintenanceGuidesTest < ActiveSupport::TestCase
  GUIDE = MaintenanceGuides::Guide.new(make: "Toyota", model: "Tacoma", model_year: 2019,
                                       url: "https://example.test/guide.pdf", title: "Toyota 2019 Tacoma Warranty & Maintenance Guide")

  def item(name, action: "replace", miles: nil, months: nil, conditions: "normal", applies_to: nil, page: 39)
    { "name" => name, "action" => action, "interval_miles" => miles, "interval_months" => months,
      "first_due_miles" => nil, "conditions" => conditions, "applies_to" => applies_to, "page" => page }
  end

  test "reads side-by-side checklists one column at a time" do
    run = Struct.new(:x, :y, :text)
    runs = [ run.new(70, 546, "5,000 miles or 6 months"), run.new(226, 546, "10,000 miles or 12 months"),
             run.new(70, 530, "Rotate tires"), run.new(226, 530, "Replace engine oil and oil filter") ]

    columns = MaintenanceGuides::PdfText.columns(runs, 396)

    assert_equal [ "5,000 miles or 6 months\nRotate tires", "10,000 miles or 12 months\nReplace engine oil and oil filter" ], columns
  end

  test "splits columns at the middle of the visible page when the sheet is cropped" do
    run = Struct.new(:x, :y, :text)
    runs = [ run.new(158, 664, "5,000 miles or 6 months"), run.new(312, 664, "10,000 miles or 12 months"),
             run.new(146, 620, "Rotate tires"), run.new(305, 620, "Replace engine oil and oil filter") ]

    columns = MaintenanceGuides::PdfText.columns(runs, 396, left: 90) # a 612-wide sheet cropped to 90..486

    assert_equal "10,000 miles or 12 months\nReplace engine oil and oil filter", columns.last
  end

  test "keeps replaced items under normal conditions, mapped to the schedule's names" do
    result = MaintenanceGuides::Validator.new(GUIDE).check("items" => [
      item("Replace engine oil and oil filter", miles: 10_000, months: 12),
      item("Replace spark plugs", miles: 60_000, applies_to: "2GR-FKS engine only", page: 45),
      item("Rotate tires", action: "rotate", miles: 5_000, months: 6),
      item("Inspect brake linings", action: "inspect", miles: 5_000),
      item("Replace transfer case oil", conditions: "special", miles: 30_000)
    ])

    assert_equal "ok", result.status
    assert_equal [ "Oil and filter change", "Spark plugs", "Tire rotation" ], result.rows.map { _1[:name] }
    assert_equal({ name: "Spark plugs", guide_wording: "Replace spark plugs", interval_miles: 60_000, interval_months: nil,
                   first_due_miles: nil, applies_to: "2GR-FKS engine only", source_page: 45,
                   source_url: GUIDE.url, source_title: GUIDE.title }, result.rows.second)
    assert_equal [ "inspect, not a cost", "only for special conditions" ], result.skipped.map { _1[:why] }
  end

  test "flags a reading that can't be right" do
    result = MaintenanceGuides::Validator.new(GUIDE).check("items" => [
      item("Replace spark plugs", miles: 500),
      item("Replace cabin air filter"),
      item("Replace engine air filter", miles: 30_000), item("Replace engine air filter", miles: 15_000)
    ])

    assert_equal "needs_review", result.status
    assert_includes result.problems, "Spark plugs: every 500 miles is outside 30000–150000"
    assert_includes result.problems, "Cabin air filter: no interval given"
    assert_includes result.problems, "Engine air filter: listed more than once with different intervals"
    assert_includes result.problems, "No oil change found, so the schedule was probably misread"
  end

  def page(number, *columns) = MaintenanceGuides::PdfText::Page.new(number:, columns:)

  test "splits pages into one normal-driving checklist per mileage" do
    pages = [
      page(39, "MAINTENANCE LOG\n5,000 miles or 6 months\nRotate tires\nAdditional Maintenance Items for\nReplace engine oil and oil filter",
               "10,000 miles or 12 months\nReplace engine oil and oil filter\nNOTE: If 0W-20 oil WAS NOT used,\nreplace engine oil and oil filter.\nRotate tires"),
      page(46, "60,000 miles or 72 months\nRotate tires\nDriving while towing:\nReplace transfer case oil (4WD)",
               "Replace spark plugs (2GR-FKS engine only)")
    ]

    checklists = MaintenanceGuides::Checklists.from(pages)

    assert_equal [ 5_000, 10_000, 60_000 ], checklists.map(&:miles)
    assert_equal "Rotate tires", checklists[0].text # towing, dusty-road and short-trip extras left out
    assert_equal "Replace engine oil and oil filter\nRotate tires", checklists[1].text # conditional note left out
    assert_equal "Rotate tires\nReplace spark plugs (2GR-FKS engine only)", checklists[2].text # right half joins the page's checklist
    assert_equal [ 39, 39, 46 ], checklists.map(&:page)
  end

  test "keeps a list that starts in the left column when the page's only heading is on the right" do
    checklists = MaintenanceGuides::Checklists.from([ page(42, "Inspect wiper blades\nReplace cabin air filter\nReplace engine air filter",
                                                              "Maintenance Log\n30,000 miles or 36 months\n_ Radiator and condenser") ])

    assert_equal [ "Replace cabin air filter", "Replace engine air filter", "_ Radiator and condenser" ], checklists.sole.text.lines(chomp: true) & [ "Replace cabin air filter", "Replace engine air filter", "_ Radiator and condenser" ]
  end

  test "doubts a reading with checklists that came back empty" do
    result = MaintenanceGuides::Validator.new(GUIDE).check(
      "items" => [ item("Replace engine oil and oil filter", miles: 10_000, months: 12) ],
      "checklists" => [ { "miles" => 10_000, "items" => [ { "name" => "Replace engine oil and oil filter" } ] }, { "miles" => 30_000, "items" => [] } ]
    )

    assert_equal "needs_review", result.status
    assert_includes result.problems, "Nothing to replace was read from the 30,000-mile checklists, so they were probably misread"
  end

  test "works out intervals from the mileages an item shows up at" do
    checklist = ->(miles, page = 39) { MaintenanceGuides::Checklists::Checklist.new(miles:, months: miles / 5_000 * 6, page:, text: "") }
    oil = { "name" => "Replace engine oil and oil filter", "action" => "replace", "applies_to" => nil }
    readings = [ 10_000, 20_000, 30_000 ].map { |miles| [ checklist.(miles), [ oil.merge("name" => miles == 20_000 ? "replace engine oil and oil filter" : oil["name"]) ] ] }
    readings << [ checklist.(60_000, 46), [ { "name" => "Replace spark plugs", "action" => "replace", "applies_to" => "2GR-FKS engine only" } ] ]
    readings << [ checklist.(100_000, 51), [ { "name" => "Replace engine coolant", "action" => "replace", "applies_to" => nil } ] ]

    items = MaintenanceGuides::Intervals.from(readings).index_by { _1["name"] }

    assert_equal [ 10_000, 12, nil, [ 10_000, 20_000, 30_000 ] ], items["Replace engine oil and oil filter"].values_at("interval_miles", "interval_months", "first_due_miles", "seen_at_miles")
    assert_equal [ 60_000, "2GR-FKS engine only", 46 ], items["Replace spark plugs"].values_at("interval_miles", "applies_to", "page")
    assert_equal 100_000, items["Replace engine coolant"]["interval_miles"]
  end

  # Stands in for Anthropic::Client: answers with the given items and keeps each request.
  class FakeClaude
    Answer = Struct.new(:stop_reason, :content, :usage)
    Block = Struct.new(:type, :text)
    Usage = Struct.new(:input_tokens, :output_tokens)

    attr_reader :requests

    def initialize(items, stop_reason: :end_turn) = (@items, @stop_reason, @requests = items, stop_reason, [])
    def messages = self

    def create(**request)
      @requests << request
      Answer.new(@stop_reason, [ Block.new(:text, { items: @items }.to_json) ], Usage.new(9_800, 1_200))
    end
  end

  test "reads every schedule page in one request to Claude, naming the car, then merges the pages" do
    booklet = MaintenanceGuides::Guide.new(make: "Subaru", model: "Outback", model_year: 2020, url: "https://example.test/book.pdf",
                                           title: "Subaru booklet", kind: :all_models_booklet)
    claude = FakeClaude.new([ item("Replace engine oil and filter", miles: 6_000, months: 6, page: 20),
                              item("Replace engine oil and filter", miles: 6_000, months: 6, page: 21),
                              item("Replace cabin air filter", miles: 30_000, page: 21) ])

    result = MaintenanceGuides::ClaudeExtractor.new(client: claude).extract([ page(20, "Engine oil: every 6,000 miles"), page(21, "Cabin filter") ], guide: booklet)

    assert_equal 1, claude.requests.size
    prompt = claude.requests.first.dig(:messages, 0, :content)
    assert_match "for the 2020 Subaru Outback", prompt
    assert_match "only list items for the Outback", prompt
    assert_match "=== Page 21 ===\nCabin filter", prompt
    assert_equal [ [ "Replace engine oil and filter", 6_000, 20 ], [ "Replace cabin air filter", 30_000, 21 ] ],
                 result["items"].map { _1.values_at("name", "interval_miles", "page") }
    assert_equal [ "page_items", 9_800 ], result.values_at("layout", "prompt_tokens")
  end

  test "doesn't trust an answer Claude didn't finish" do
    claude = FakeClaude.new([], stop_reason: :max_tokens)

    error = assert_raises(MaintenanceGuides::ClaudeExtractor::Error) { MaintenanceGuides::ClaudeExtractor.new(client: claude).extract([ page(39, "Rotate tires") ]) }
    assert_match "stopped early", error.message
  end

  test "says plainly when there's no Claude API key" do
    Claude.stub_key(nil) do
      assert_raises(MaintenanceGuides::ClaudeExtractor::Unavailable) { MaintenanceGuides::ClaudeExtractor.new.extract([ page(39, "Rotate tires") ]) }
      assert_nil MaintenanceGuides::Reader.new.instance_variable_get(:@extractor), "without a key the reader goes rules-only"
    end
  end

  test "keeps the pages that look most like a schedule when a manual is long" do
    pages = (1..30).map { |number| page(number, "Seats and mirrors") }
    pages[11] = page(12, "Maintenance schedule\n7,500 miles 15,000 miles 22,500 miles")
    pages[12] = page(13, "Every 30,000 miles replace the engine air filter")

    kept = MaintenanceGuides::PdfText.most_schedule_like(pages, max: 3)

    assert_equal [ 1, 12, 13 ], kept.map(&:number), "the schedule pages, plus the earliest of the rest, in page order"
  end

  test "merges items read page by page, going with the interval most pages agree on" do
    readings = [
      [ page(70, ""), [ item("Replace engine oil and filter", miles: 7_500, months: 6), item("Replace engine oil and filter", miles: 3_750, conditions: "special") ] ],
      [ page(71, ""), [ item("Replace engine oil and filter", miles: 7_500, months: 6), item("Replace cabin air filter", miles: 22_500) ] ],
      [ page(72, ""), [ item("Replace engine oil and filter", miles: 5_000, months: 6) ] ]
    ]

    items = MaintenanceGuides::Intervals.from_pages(readings)

    assert_equal [ [ "Replace engine oil and filter", 7_500, 6, "normal", 70 ], [ "Replace engine oil and filter", 3_750, nil, "special", 70 ],
                   [ "Replace cabin air filter", 22_500, nil, "normal", 71 ] ],
                 items.map { _1.values_at("name", "interval_miles", "interval_months", "conditions", "page") }
  end

  class FakeFinder
    def initialize(guides) = @guides = guides
    def find(make:, model:, model_year:) = @guides["#{model_year} #{make} #{model}"]
  end

  class FakeReader
    def initialize(&block) = @block = block
    def read(guide) = @block.call(guide)
  end

  def reading(guide, status: "ok", problems: [])
    rows = [ { name: "Oil and filter change", interval_miles: 10_000, interval_months: 12 } ]
    MaintenanceGuides::Reader::Read.new(guide:, pages: [], extraction: { "layout" => "mileage_checklists", "model" => "claude-sonnet-5-5", "checklists" => [] },
                                        result: MaintenanceGuides::Validator::Result.new(status:, rows:, skipped: [], problems:))
  end

  def with_prefill_dirs
    dir = Pathname(Dir.mktmpdir)
    seed_dir, error_log = MaintenanceGuides::Prefill.seed_dir, MaintenanceGuides::Prefill.error_log
    MaintenanceGuides::Prefill.seed_dir, MaintenanceGuides::Prefill.error_log = dir.join("seeds"), dir.join("errors.jsonl")
    yield
  ensure
    MaintenanceGuides::Prefill.seed_dir, MaintenanceGuides::Prefill.error_log = seed_dir, error_log
    FileUtils.rm_rf(dir)
  end

  test "prefills each car, logs the ones that fail, and skips what's done on the next run" do
    with_prefill_dirs do
      car = MaintenanceGuides::Prefill::Car
      cars = [ car.new(make: "Toyota", model: "Tacoma", model_year: 2019), car.new(make: "Nissan", model: "Rogue", model_year: 2020),
               car.new(make: "Toyota", model: "Corolla", model_year: 2019), car.new(make: "Toyota", model: "Prius", model_year: 2019) ]
      nissan = GUIDE.with(make: "Nissan", model: "Rogue", model_year: 2020, kind: :owner_manual)
      finder = FakeFinder.new("2019 Toyota Tacoma" => GUIDE, "2020 Nissan Rogue" => nissan, "2019 Toyota Prius" => GUIDE.with(model: "Prius"))
      reader = FakeReader.new { |guide| guide.model == "Prius" ? raise(MaintenanceGuides::Reader::Error, "Download failed (HTTP 500)") : reading(guide) }

      counts = MaintenanceGuides::Prefill.new(finder:, reader:, out: StringIO.new).run(cars)

      assert_equal({ ok: 1, needs_review: 1, not_found: 1, failed: 1 }, counts.to_h)
      assert_equal "ok", MaintenanceGuide.find_by!(make_key: "TOYOTA", model_key: "TACOMA", model_year: 2019).status
      saved = JSON.parse(File.read(MaintenanceGuides::Prefill.seed_path(cars.second)))
      assert_equal "needs_review", saved["status"], "makes without an answer key are never trusted"
      assert_match "answer key", saved["problems"].last
      assert_equal "owner_manual", saved["kind"]
      assert_equal [ "2019 Toyota Corolla", "2019 Toyota Prius" ], MaintenanceGuides::Prefill.failures.map { "#{_1["model_year"]} #{_1["make"]} #{_1["model"]}" }

      again = MaintenanceGuides::Prefill.new(finder:, reader:, out: StringIO.new).run(cars)
      assert_equal 2, again[:already_done]
    end
  end

  test "stops the batch when Claude can't be reached" do
    with_prefill_dirs do
      reader = FakeReader.new { raise MaintenanceGuides::ClaudeExtractor::Unavailable, "No Claude API key set" }
      cars = [ MaintenanceGuides::Prefill::Car.new(make: "Toyota", model: "Tacoma", model_year: 2019) ]

      assert_raises(MaintenanceGuides::ClaudeExtractor::Unavailable) do
        MaintenanceGuides::Prefill.new(finder: FakeFinder.new("2019 Toyota Tacoma" => GUIDE), reader:, out: StringIO.new).run(cars)
      end
      assert_empty MaintenanceGuides::Prefill.failures
    end
  end
end
