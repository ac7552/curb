module MaintenanceGuides
  # Splits a guide's schedule pages into one checklist per service mileage ("30,000 miles or 36 months"),
  # keeping only what's done under normal driving. Small local models read one short checklist well and
  # sixteen pages of them badly, so this does the slicing in plain code.
  class Checklists
    Checklist = Data.define(:miles, :months, :page, :text)

    # "30,000 miles or 36 months" (Toyota) or "36 Months or 30,000 Miles" (Lexus).
    HEADING = /\A(?:(?<miles>\d{1,3}(?:,\d{3})+) miles or (?<months>\d+) months|(?<months>\d+) months or (?<miles>\d{1,3}(?:,\d{3})+) miles)\b/i
    # Where a column's extra items for towing, dusty roads, short trips and so on begin.
    SPECIAL = /\A(Additional Maintenance Items|Driving (on|while|in)\b|Repeated trips|Extensive idling|If you drive primarily under)/i

    def self.from(pages)
      pages.flat_map do |page|
        found, before = [], []
        page.columns.each do |column|
          without_notes(column.lines.map(&:strip).take_while { |line| !line.match?(SPECIAL) }).each do |line|
            if (heading = line.match(HEADING))
              found << { miles: heading[:miles].delete(",").to_i, months: heading[:months].to_i, lines: [] }
            elsif found.any?
              # A column with no heading of its own (the right half of a one-checklist page) belongs to
              # the checklist above it.
              found.last[:lines] << line
            else
              before << line
            end
          end
        end
        # Text before the first heading is usually the page title, but on a one-checklist page whose
        # heading sits atop the right column, the list starts in the left column, above the heading.
        found.first[:lines].unshift(*before) if found.one? && before.any? { |line| line.match?(/\A\W*(Replace|Rotate)\b/) }
        found.map { |checklist| Checklist.new(miles: checklist[:miles], months: checklist[:months], page: page.number, text: checklist[:lines].join("\n")) }
      end
    end

    # Drops "NOTE:" paragraphs, which run until a line ending in a full stop (at most NOTE_LINES, so a
    # note missing its full stop can't swallow the checklist). They hold conditional work ("If 0W-20 oil
    # WAS NOT used at the last oil change, replace engine oil") that isn't the normal schedule.
    NOTE_LINES = 8

    def self.without_notes(lines)
      note_lines = 0
      lines.reject do |line|
        note_lines = 1 if line.match?(/\ANOTE:/i)
        next false if note_lines.zero?
        note_lines = line.end_with?(".") || note_lines >= NOTE_LINES ? 0 : note_lines + 1
        true
      end
    end
  end
end
