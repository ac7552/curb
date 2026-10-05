module MaintenanceGuides
  # Checks a model's reading of a guide before anyone relies on it. Items are mapped to the names the
  # service schedule already uses (db/seeds/service_items.yml), intervals must fall in a believable range,
  # and a guide with no oil change is assumed misread. Anything doubtful makes the result "needs_review";
  # only "ok" results should become schedule rows.
  class Validator
    Item = Data.define(:name, :pattern, :miles)

    # Wording -> schedule name, with the range of mileage intervals makers actually use.
    ITEMS = [
      Item.new("Oil and filter change", /engine oil|oil (and )?(oil )?filter|change oil/, 3_000..15_000),
      Item.new("Cabin air filter", /\A(?!.*hepa)(?:.*)(?:cabin air filter|in-cabin|cabin (micro)?filter|microfilter|pollen filter|climate control air filter|passenger compartment air filter|air conditioning filter)/, 7_500..60_000),
      Item.new("Engine air filter", /engine air (filter|cleaner)|air cleaner|\A\W*air filter\b/, 10_000..100_000),
      Item.new("Spark plugs", /spark plug/, 30_000..150_000),
      Item.new("Coolant change", /coolant|cooling system/, 30_000..200_000),
      Item.new("Brake fluid change", /brake fluid/, 15_000..60_000),
      Item.new("Transmission fluid", /transmission fluid|transmission oil|automatic transmission|transmission\b.*\bfluid|\bcvt\b|\batf\b|\bdsg\b/, 15_000..150_000),
      Item.new("Front differential oil", /front differential/, 15_000..150_000),
      Item.new("Rear differential oil", /rear differential|differential oil/, 15_000..150_000),
      Item.new("Transfer case oil", /transfer case/, 15_000..150_000),
      Item.new("Timing belt", /timing belt/, 50_000..150_000),
      Item.new("Tire rotation", /rotat\w* (the )?tires?|tires? \(?rotation/, 3_000..15_000)
    ].freeze
    COSTED_ACTIONS = %w[replace rotate].freeze

    Result = Data.define(:status, :rows, :skipped, :problems)

    def initialize(guide)
      @guide = guide
    end

    # extraction: { "items" => [...] } from RuleExtractor or ClaudeExtractor.
    def check(extraction)
      rows, skipped, problems = [], [], []
      Array(extraction["items"]).each do |raw|
        name = raw["name"].to_s
        item = ITEMS.find { |candidate| name.downcase.match?(candidate.pattern) }
        if raw["conditions"] != "normal" || !COSTED_ACTIONS.include?(raw["action"]) || item.nil?
          skipped << { name:, why: skip_reason(raw, item) }
          next
        end

        miles, months, first = raw.values_at("interval_miles", "interval_months", "first_due_miles").map { |value| value&.to_i }
        problems << "#{item.name}: no interval given" if miles.nil? && months.nil?
        problems << "#{item.name}: every #{miles} miles is outside #{item.miles.minmax.join("–")}" if miles && !item.miles.cover?(miles)
        problems << "#{item.name}: every #{months} months isn't believable" if months && !months.between?(1, 240)
        rows << { name: item.name, guide_wording: name, interval_miles: miles, interval_months: months,
                  first_due_miles: first, applies_to: raw["applies_to"], source_page: raw["page"] }
      end

      # The same item twice is fine if it agrees with itself; two different intervals for one car isn't.
      rows = rows.uniq { _1.values_at(:name, :interval_miles, :interval_months, :applies_to) }
      conflicting = rows.group_by { _1.values_at(:name, :applies_to) }.select { |_, same| same.size > 1 }.keys.map(&:first)
      problems.concat(conflicting.map { |name| "#{name}: listed more than once with different intervals" })
      unless rows.any? { _1[:name] == "Oil and filter change" } || extraction["electric"]
        problems << (extraction["layout"] == "sentences" ? "No fixed oil change interval: the car's maintenance reminder decides when, from how it's driven" : "No oil change found, so the schedule was probably misread")
      end
      empty = Array(extraction["checklists"]).select { _1["miles"] && _1["items"].blank? }.map { _1["miles"].to_fs(:delimited) }
      problems << "Nothing to replace was read from the #{empty.to_sentence}-mile checklists, so they were probably misread" if empty.any?

      Result.new(status: problems.empty? ? "ok" : "needs_review", rows: rows.map { _1.merge(source_url: @guide.url, source_title: @guide.title) },
                 skipped:, problems:)
    end

    private
      def skip_reason(raw, item)
        if raw["conditions"] != "normal" then "only for special conditions"
        elsif !COSTED_ACTIONS.include?(raw["action"]) then "#{raw["action"]}, not a cost"
        else "not an item the schedule prices yet"
        end
      end
  end
end
