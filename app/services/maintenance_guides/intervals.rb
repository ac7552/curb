module MaintenanceGuides
  # Works out how often each item is done from the checklists it appears on: an item replaced at 20,000,
  # 40,000 and 60,000 miles is every 20,000. Done in code rather than by the model, which can't be trusted
  # with arithmetic across a whole schedule.
  module Intervals
    module_function

    # readings: [[Checklist, [{ "name", "action", "applies_to" }]]]. Returns items in the shape the
    # Validator checks.
    def from(readings)
      months_at = readings.to_h { |checklist, _| [ checklist.miles, checklist.months ] }
      seen = Hash.new { |hash, key| hash[key] = [] }
      readings.each do |checklist, items|
        items.each { |item| seen[group_key(item)] << [ checklist, item ] }
      end

      seen.values.map do |sightings|
        miles = sightings.map { |checklist, _| checklist.miles }.uniq.sort
        interval = miles.each_cons(2).map { |a, b| b - a }.min || miles.first
        first_checklist, first_item = sightings.min_by { |checklist, _| checklist.miles }
        {
          "name" => first_item["name"], "action" => first_item["action"],
          "interval_miles" => interval, "interval_months" => months_at[interval] || months_like(interval, months_at),
          "first_due_miles" => (miles.first if miles.first != interval), "conditions" => "normal",
          "applies_to" => first_item["applies_to"].presence, "page" => first_checklist.page,
          "seen_at_miles" => miles
        }
      end
    end

    # readings: [[PdfText::Page, [{ "name", "action", "interval_miles", ... }]]] from reading a schedule
    # page by page. The same item often shows up on several pages (a table, then a summary); its interval
    # is the one most pages agree on, and its page the first it appears on. Special-conditions items are
    # kept as they are, for the Validator to set aside.
    def from_pages(readings)
      sightings = readings.flat_map { |page, items| items.map { |item| [ page, item ] } }
      sightings.group_by { |_, item| [ group_key(item), item["conditions"] ] }.map do |_, same|
        agreed = same.map { |_, item| item.values_at("interval_miles", "interval_months") }.tally.max_by { |pair, count| [ count, pair.compact.size ] }.first
        page, item = same.min_by { |page, _| page.number }
        item.merge("interval_miles" => agreed[0], "interval_months" => agreed[1], "page" => page.number)
      end
    end

    # The same item can be worded differently from one checklist to the next; its schedule name and any
    # limit ("4WD", "2GR-FKS engine only") are what identify it.
    def group_key(item)
      name = item["name"].to_s.downcase
      known = Validator::ITEMS.find { |candidate| name.match?(candidate.pattern) }&.name
      [ known || name.gsub(/\(.*?\)|\d+\z/, "").squish, item["applies_to"].to_s.downcase.gsub(/[^a-z0-9]/, "").presence ]
    end

    # Months for an interval with no checklist of its own, at the guide's miles-to-months rate.
    def months_like(miles, months_at)
      rate = months_at.map { |at_miles, months| months.to_f / at_miles }.sum / months_at.size
      (miles * rate).round if months_at.any?
    end
  end
end
