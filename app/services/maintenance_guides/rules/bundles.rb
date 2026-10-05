module MaintenanceGuides
  module Rules
    # Reads schedules made of service bundles, as Volkswagen and Audi file them with NHTSA: a grid saying
    # which bundle is due when ("Minor Maintenance" at 10K, 30K, 50K …; "Standard Maintenance (Includes All
    # Minor Maintenance Items)" at 20K, 40K …), a list of the jobs in each bundle ("Engine: Change oil and
    # replace filter", "Engine Oil and Oil filter - Change oil and replace filter"), and a table of other
    # jobs with their own intervals and the models they're for ("Air filter - Replace | Every 60,000
    # miles | All vehicles except RS7 and A8 LWB").
    #
    # Works on the PDF's text as laid out, where columns line up by character.
    module Bundles
      module_function

      BUNDLE = /\A(minor|standard|extended)\s*maintenance/i
      HEADER = /\b\d{1,3}K\b/
      ADDITIONAL = /\A\s*additional\s*maintenance\s*items\s*\z/i

      # Items in the Validator's shape, each with the models it's for in "applies_to" (or nil for all).
      def items(page_texts)
        # Bullets come through as control characters; as spaces they keep the columns lined up.
        lines = page_texts.each_with_index.flat_map { |text, index| text.lines.map { [ _1.gsub(/[[:cntrl:]]/, " ").rstrip, index + 1 ] } }
        due = due_at(lines)
        return [] if due.empty?

        bundle_items(lines, due) + additional_items(lines)
      end

      # { "minor" => { miles: [10000, 30000, …], months: 12, includes: [] }, … } from the grid at the top.
      def due_at(lines)
        header_index = lines.index { |line, _| line.scan(HEADER).size >= 4 } or return {}
        header = lines[header_index].first
        columns = header.enum_for(:scan, /(\d{1,3})K/i).map { [ Regexp.last_match.begin(0) + Regexp.last_match[0].length / 2.0, Regexp.last_match[1].to_i * 1000 ] }

        lines[(header_index + 1)..(header_index + 12)].each_with_index.each_with_object({}) do |((line, _), offset), due|
          name = line.strip[BUNDLE, 1]&.downcase or next
          marks = line.enum_for(:scan, /\bX\b/).map { Regexp.last_match.begin(0) }
          next if marks.empty?
          miles = marks.map { |at| columns.min_by { |column_at, _| (column_at - at).abs }.last }.uniq.sort
          following = lines[header_index + 1 + offset + 1]&.first.to_s
          months = following[/every\s+(\d+)\s+years?/i, 1]&.to_i&.*(12)
          due[name] = { miles:, months: }
        end
      end

      # The jobs listed under each bundle's heading. A bundle that "Includes All Minor Maintenance Items"
      # brings those jobs along, so the oil change in Minor is done at Standard's mileages too.
      def bundle_items(lines, due)
        contents = Hash.new { |hash, key| hash[key] = [] }
        includes = {}
        current = nil
        lines.each do |line, page|
          text = line.strip
          if (name = text[/\A(minor|standard|extended)\s*maintenance(\s*\(continued\))?(\s*\(includes all (\w+) maintenance items\))?\z/i, 1])
            current = name.downcase
            includes[current] = text[/includes all (\w+)/i, 1]&.downcase if text.match?(/includes all/i)
          elsif text.match?(ADDITIONAL) || text.match?(/\Awork to be completed/i)
            current = nil
          elsif current && line.match?(/\A\s{1,3}\S/) && (job = job_of(text))
            contents[current] << [ job, page ]
          end
        end

        # A job listed in several bundles (VW repeats the oil change under Standard) is done at all of their
        # mileages, as is a job in a bundle that another includes.
        found_in = Hash.new { |hash, key| hash[key] = [] }
        contents.each { |bundle, jobs| jobs.each { |name, page| found_in[[ name, page ]] |= [ bundle ] } }
        found_in.group_by { |(name, _), _| name }.map do |name, entries|
          page = entries.map { |(_, page), _| page }.min
          bundles = entries.flat_map(&:last).uniq
          bundles |= includes.select { |_, included| bundles.include?(included) }.keys
          miles = bundles.flat_map { due.dig(_1, :miles) || [] }.uniq.sort
          next if miles.empty?
          interval = miles.each_cons(2).map { |a, b| b - a }.min || miles.first
          { "name" => name, "action" => Sentences.action(name.split(/:| - /, 2).last.to_s) || "replace",
            "interval_miles" => interval, "interval_months" => bundles.filter_map { due.dig(_1, :months) }.min,
            "first_due_miles" => (miles.first if miles.first != interval), "conditions" => "normal", "applies_to" => nil, "page" => page }
        end.compact
      end

      # "Engine: Change oil and replace filter" or "Brake fluid - Change": a job only when what's done is a
      # change or replacement.
      def job_of(text)
        thing, work = text.split(/:\s*|\s+-\s+/, 2)
        return unless work&.match?(/\A(change|replace)\b/i)
        "#{thing}: #{work}".sub(/\s*\(if equipped\)\s*/i, " ").squish
      end

      # Rows of the "Additional Maintenance Items" table: what's done, how often, and (Audi) for which
      # models. Cells wrap onto the lines below, so each piece of text goes to the column it starts under:
      # the table's heading row gives the columns (Audi), or else the first row does (VW).
      def additional_items(lines)
        start = lines.index { |line, _| line.match?(ADDITIONAL) } or return []
        rows = []
        columns = indent = nil
        lines[(start + 1)..].each do |line, page|
          next if line.strip.empty? || line.match?(ADDITIONAL) || line.match?(/\A\s{20,}\d+\s{10,}/) # page footers
          pieces = line.enum_for(:scan, /\S+(?: {1,2}\S+)*/).map { [ Regexp.last_match.begin(0), Regexp.last_match[0] ] }
          if line.match?(/\A\s*work to be completed/i)
            columns = pieces.drop(1).map(&:first)
            next
          end
          # A row starts where the table's first row does; its wrapped lines are indented further.
          indent ||= pieces.first.first if pieces.first.last.match?(/\A[A-Z0-9]/)
          new_row = indent && pieces.first.first <= indent + 1 && pieces.first.last.match?(/\A[A-Z0-9]/)
          columns ||= pieces.drop(1).map(&:first) if new_row && pieces.size >= 2
          next unless columns && (new_row || rows.any?)

          rows << { work: +"", interval: +"", models: +"", page: } if new_row
          pieces.each do |at, text|
            cell = if at < columns[0] - 3 then :work elsif columns[1].nil? || at < columns[1] - 3 then :interval else :models end
            rows.last[cell] << " " << text
          end
        end

        rows.filter_map do |row|
          work = row[:work].squish
          interval = row[:interval].squish
          found = Sentences.interval(interval.sub(/\A(?=\d)/, "every ")) or next
          only = [ work, interval ].filter_map { _1[/\(([^)]*only[^)]*)\)/i, 1] }
          # Rows for different versions of one job ("6-Speed DSG transmission fluid" every 40K, "Automatic
          # transmission fluid (non DSG)" every 80K) say which version they're for.
          version = work[/\b(\d-speed dsg|dsg|automatic|manual|\d\.\d ?l|\d cyl)\b/i]
          models = [ row[:models].squish.presence, *only, version ].compact.join("; ")
          { "name" => work.sub(/\s*\(if equipped\)/i, ""), "action" => work.match?(/\b(replace|change)\b/i) ? "replace" : "inspect",
            "conditions" => "normal", "applies_to" => models.presence, "page" => row[:page] }.merge(found)
        end
      end
    end
  end
end
