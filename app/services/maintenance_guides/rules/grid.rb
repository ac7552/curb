module MaintenanceGuides
  module Rules
    # Reads schedules printed as a grid (Nissan, Infiniti, Mazda, Subaru, Hyundai, GM): one column per
    # mileage, one row per job, and a mark where the job is due: R(eplace), I(nspect), or a check mark.
    # Works from where each piece of text sits on the page, since the grid's columns only line up visually.
    #
    # Column headings are found either as a row of numbers ("×1000 miles 7.5 15 22.5 …") or, when printed
    # sideways (GM), by reading the letters stacked above each column of marks ("12000km/7,500mi"). Notes
    # written in a row instead of marks ("Rotate every 12,000 km (7,500 miles).") are read by Sentences.
    # A schedule that runs over several pages is put back together before intervals are worked out, and a
    # page with no heading of its own belongs to the schedule before it (normal or severe driving).
    class Grid
      Token = Data.define(:x, :y, :text)
      Column = Data.define(:x, :miles, :months)
      Row = Data.define(:label, :marks, :notes, :page, :conditions)

      LETTER_MARKS = { "R" => "replace", "I" => "inspect", "T" => "other", "L" => "other", "C" => "other", "D" => "other", "P" => "other", "A" => "other" }.freeze
      CHECK_MARKS = %w[@ ✓ ✔ ● ■ ○ x X].freeze
      NUMBER = /\A\(?(\d{1,3}(?:[.,]\d+)?)\)?\z/
      LINE_GAP = 3.0 # points: text this close vertically is one line
      SPECIAL = /severe|premium\s*maintenance|special\s*operating|demanding|additional\s*maintenance\s*items/i
      NORMAL = /\bnormal\b|standard\s*maintenance/i

      # reader: anything with pages and page(n) like PDF::Reader's (tests pass pages built by hand).
      # texts: each page's plain text, if already pulled out (to skip pages without a grid quickly).
      def initialize(pdf_path = nil, reader: nil, texts: nil)
        @reader = reader || (PdfSpacingFix.apply && PDF::Reader.new(pdf_path.to_s))
        @texts = texts
      end

      # Pages that hold a grid, by number.
      def pages = rows.map(&:page).uniq

      # Items in the Validator's shape.
      def items
        months_at = {}
        rows.each { |row| row.marks.each { |column, _| months_at[column.miles] ||= column.months if column.months } }
        rows.group_by { [ key(_1.label), _1.conditions ] }.flat_map do |_, same|
          row = Row.new(label: same.first.label, marks: same.flat_map(&:marks), notes: same.flat_map(&:notes),
                        page: same.first.page, conditions: same.first.conditions)
          row_items(row, months_at)
        end
      end

      private
        def rows
          @rows ||= begin
            conditions = "normal"
            previous = nil # [page index, columns] of the last page with a grid
            pages = @reader.pages
            pages.each_with_index.flat_map do |page, index|
              # Building words letter by letter is slow, so skip most of a manual; but always look at the page
              # after a grid, which may carry it on.
              next [] unless might_hold_grid?(page, index) || previous&.first == index - 1
              sign, tokens, lines, columns, header_y = [ 0, 1, -1 ].lazy.filter_map do |sign|
                turned = turn(page.runs(merge: false), sign)
                tokens = tokens(turned)
                lines = lines_of(tokens)
                found = horizontal_columns(lines) || sideways_columns(turned, tokens) || carried_columns(tokens, previous)
                [ sign, tokens, lines, *found ] if found && found.first.size >= 4
              end.first
              previous = (sign && index) ? [ index, columns ] : previous
              next [] unless sign

              conditions = heading_conditions(lines) || conditions
              # Footnotes sit under the grid or on the next page; "(1)" beside a job's name is a reference.
              bottom = tokens.select { LETTER_MARKS.key?(_1.text) || CHECK_MARKS.include?(_1.text) }.map(&:y).min || 0
              following = pages[index + 1] ? tokens(turn(pages[index + 1].runs(merge: false), sign)) : []
              notes = footnotes(tokens.select { _1.y < bottom - 4 }).merge(footnotes(following)) { |_, here, _| here }
              page_rows(lines.select { |line| line.first.y < header_y - 1 }, columns, index + 1, conditions).map do |row|
                ref = row.label[/\((\d{1,2})\)\s*\z/, 1]
                ref && notes[ref] ? row.with(notes: row.notes + [ [ nil, notes[ref] ] ]) : row
              end
            end
          end
        end

        # A grid's page names its columns: "×1000 miles", "Miles x 1,000", "10K", or GM's "7,500 mi/". A grid
        # printed sideways (Genesis, Jaguar) comes out jumbled, but still has a crowd of lone R and I marks.
        GRID_HINT = /[x×]\s*1,?000|miles\s*x|\b\d{1,3}K\b|\d,\d{3}\s*mi\b|\bmi\/|months?:?\s*\d+\s+\d+/i

        def might_hold_grid?(page, index)
          text = @texts&.[](index) || (page.text if page.respond_to?(:text))
          text.nil? || text.match?(GRID_HINT) || text.scan(/(?<![\w.])[RIX@●✓✔](?![\w.])/).size >= 20
        end

        Turned = Struct.new(:x, :y, :width, :font_size, :text)

        # The page's letters as printed (sign 0), or turned a quarter one way or the other (1, -1), for a
        # grid printed sideways on the page: once turned, its rows read across like any other grid.
        def turn(chars, sign)
          return chars if sign.zero?
          chars.map { |c| Turned.new(sign * c.y, -sign * c.x, c.width, c.font_size, c.text) }
        end

        # Words placed by their middle, so a mark lines up with the column heading above it.
        def tokens(chars)
          PdfText.words(chars).map { Token.new(x: _1.x + _1.width / 2.0, y: _1.y, text: _1.text) }
        end

        # Footnotes by number ("(7)" => "Replace brake fluid every five years."), read column by column:
        # GM sets them in three columns under the grid, or on the page after it.
        def footnotes(tokens)
          markers = tokens.select { _1.text.match?(/\A\(\d{1,2}\)\z/) }
          starts = markers.map { _1.x.round }.sort.chunk_while { |a, b| b - a <= 12 }.map(&:min)
          return {} if starts.empty?
          body = tokens.select { |token| token.y <= markers.map(&:y).max + 1 && token.x >= starts.first - 12 }
          starts.each_with_index.flat_map do |start, i|
            right = starts[i + 1] ? starts[i + 1] - 12 : Float::INFINITY
            text = lines_of(body.select { _1.x >= start - 12 && _1.x < right }).map { |line| line.map(&:text).join(" ") }.join(" ")
            text.scan(/\((\d{1,2})\)\s*(.*?)(?=\s\(\d{1,2}\)\s|\z)/m)
          end.to_h
        end

        def lines_of(tokens)
          tokens.sort_by { -_1.y }.chunk_while { |a, b| (a.y - b.y).abs <= LINE_GAP }.map { |line| line.sort_by(&:x) }
        end

        # A row of four or more rising numbers labeled in miles ("×1000 miles", "Miles x 1,000", "x 1,000 mi"),
        # with an optional months row. Numbers in brackets are kilometers.
        def horizontal_columns(lines)
          miles_row = months_row = nil
          lines.each_with_index do |line, index|
            # "x 1,000 mi" and "(km x 1,000)" are labels, not column headings.
            numbers = line.each_with_index.select do |token, i|
              token.text.match?(NUMBER) && token.text.count("(") == token.text.count(")") &&
                !line[i + 1]&.text&.match?(/\A\(?(mi|miles|km)\b/i) && !line[i - 1]&.text&.match?(/\A[x×]\z/i)
            end.map(&:first)
            next if numbers.size < 4 || numbers.count { _1.text.start_with?("(") } > numbers.size / 2 # kilometers
            values = numbers.map { _1.text[NUMBER, 1].tr(",", ".").to_f }
            next unless values.each_cons(2).all? { |a, b| b > a }

            label = line.select { _1.x < numbers.first.x }.map(&:text).join(" ")
            above = index.positive? ? lines[index - 1].map(&:text).join(" ") : ""
            # The label sits beside the numbers or, on some pages (Nissan), on the line above them. A
            # "miles x 1,000" label wins over a sentence that mentions months.
            multiplier = /(miles|mi)\s*[x×]\s*1,?000|[x×]\s*1,?000\s*(miles|mi)\b/i
            if label.match?(multiplier) || (label.blank? && above.match?(multiplier))
              miles_row ||= [ numbers.zip(values), line.first.y ]
            elsif label.match?(/\bmonths?\W*\z/i) || (label.blank? && above.match?(/\bmonths?\W*\z/i))
              months_row ||= numbers.zip(values)
            elsif label.match?(/\bmi(les)?\b|mileage/i) || ("#{label} #{above}".match?(/\bmi(les)?\b|mileage/i) && !label.match?(/\bkm\b/i))
              miles_row ||= [ numbers.zip(values), line.first.y ]
            end
          end
          return unless miles_row

          numbers, y = miles_row
          scale = numbers.map(&:last).max < 1000 ? 1000 : 1
          gap = numbers.each_cons(2).map { |(a, _), (b, _)| b.x - a.x }.min
          columns = numbers.each_with_index.map do |(token, value), i|
            month = months_row&.size == numbers.size ? months_row[i] : months_row&.min_by { |m, _| (m.x - token.x).abs }
            month = nil if month && (month.first.x - token.x).abs > gap * 0.6
            Column.new(x: token.x, miles: (value * scale).round, months: month&.last&.round)
          end
          [ columns, [ y, *months_row&.map { _1.first.y } ].min ]
        end

        # A page that carries the grid on without repeating its headings (Mitsubishi): the columns of the page
        # just before, if this page has marks lined up under them.
        def carried_columns(tokens, previous)
          index, columns = previous
          return unless columns
          # A page with a heading row of its own (kilometers only, say) is a different table, not this one.
          return if lines_of(tokens).any? { |line| (numbers = line.map(&:text).grep(NUMBER)).size >= 4 && numbers.map(&:to_f).each_cons(2).all? { |a, b| b > a } }
          marks = tokens.select { LETTER_MARKS.key?(_1.text) || CHECK_MARKS.include?(_1.text) }
          gap = columns.each_cons(2).map { |a, b| b.x - a.x }.min
          lined_up = marks.count { |mark| columns.any? { (_1.x - mark.x).abs <= gap * 0.4 } }
          [ columns, (tokens.map(&:y).max || 0) + 2 ] if marks.size >= 6 && lined_up >= marks.size * 0.8
        end

        # GM prints its mileages sideways above each column. Columns are where the check marks line up; the
        # letters stacked above each, read bottom to top, give "12000km/7,500mi".
        def sideways_columns(chars, tokens)
          marks = tokens.select { CHECK_MARKS.include?(_1.text) }
          return if marks.size < 8
          xs = marks.map { _1.x.round }.sort.chunk_while { |a, b| b - a <= 4 }.map { _1.sum.to_f / _1.size }
          top = marks.map(&:y).max
          letters = chars.select { _1.y > top + 2 }
          stacked = ->(x, above = top + 2) { letters.select { |c| c.y > above && (c.x + c.width / 2.0 - x).abs < 5 }.sort_by(&:y).map(&:text).join }
          columns = xs.filter_map do |x|
            miles = stacked.(x)[/([\d,]+)\s*mi/, 1]&.delete(",")&.to_i
            Column.new(x:, miles:, months: nil) if miles&.positive?
          end
          columns = stacked_digit_columns(xs, tokens, top, stacked) if columns.size < 4
          [ columns, top + 12 ] if columns && columns.size >= 4 # the first job's name can sit a line or two above its marks
        end

        # Mopar (Jeep, Chrysler, Dodge, Ram) stacks bare digits above each column: miles on top, then an "Or
        # Months: 12 24 36" row, then kilometers. The miles are the digits above the months row.
        def stacked_digit_columns(xs, tokens, top, stacked)
          months_line = lines_of(tokens.select { _1.y > top }).find do |line|
            numbers = line.map(&:text).grep(/\A\d{1,3}\z/).map(&:to_i)
            numbers.size >= 4 && numbers.each_cons(2).all? { |a, b| b > a } && line.map(&:text).join(" ").match?(/month/i)
          end
          return unless months_line
          months_y = months_line.map(&:y).max
          xs.filter_map do |x|
            miles = stacked.(x, months_y + 2)[/\A[\d,]+/]&.delete(",")&.to_i
            month = months_line.select { _1.text.match?(/\d/) }.min_by { (_1.x - x).abs }
            Column.new(x:, miles:, months: month.text[/\d+/].to_i) if miles&.positive?
          end
        end

        # "normal" or "special" when the page's heading says ("Standard maintenance", "Schedule 2 … severe"),
        # nil when it doesn't (a page that carries a schedule on). A heading that only gives a schedule's number
        # goes by what the guide says that number is for: Mazda's Schedule 1 is normal driving, Mitsubishi's
        # is "Use Schedule 1 if you primarily operate your vehicle under" hard conditions.
        def heading_conditions(lines)
          heading = lines.first(14).flatten.map(&:text).join(" ")
          if heading.match?(SPECIAL) && !heading.match?(NORMAL) then "special"
          elsif heading.match?(NORMAL) then "normal"
          elsif (number = heading[/schedule\s*(\d)/i, 1])
            severe_schedules.include?(number) ? "special" : "normal"
          end
        end

        # Schedule numbers the guide says are for hard driving. "Use Schedule 1 if you primarily operate your
        # vehicle under …" (Mitsubishi) is; "Follow Schedule 1 if the vehicle is operated mainly where none of
        # the following conditions (severe driving …)" (Mazda) isn't; "Schedule 2 … Severe driving conditions" is.
        def severe_schedules
          @severe_schedules ||= begin
            text = (@texts || @reader.pages.map { _1.respond_to?(:text) ? _1.text : "" }).join(" ").dup.force_encoding("UTF-8").scrub.gsub(/\s+/, " ")
            choices = text.scan(/(?:use|follow)\s+schedule\s*(\d)\s+if([^.]{0,120})/i)
            normal, severe = choices.partition { |_, rest| rest.match?(/\b(none|not|no)\b/i) }.map { |list| list.map(&:first) }
            (severe | text.scan(/schedule\s*(\d)(?:(?!schedule|none|not)[^.]){0,80}?(?:severe|demanding)/i).flatten) - normal
          end
        end

        # A page's lines as rows. Text left of the first column names the job; marks and notes sit in the
        # columns. A name may wrap onto a second line, and marks or a note may sit on a line of their own
        # next to the name; they belong to the nearest name within a line and a half.
        def page_rows(lines, columns, page, conditions)
          gap = columns.each_cons(2).map { |a, b| b.x - a.x }.min
          left_edge = columns.first.x - gap * 0.6
          label_start = lines.filter_map { |line| line.first.x if line.first.x < left_edge }.min || 0
          parsed = lines.map do |line|
            names, cells = line.partition { _1.x < left_edge }
            marks = cells.filter_map do |token|
              next unless LETTER_MARKS.key?(token.text) || CHECK_MARKS.include?(token.text)
              column = columns.min_by { (_1.x - token.x).abs }
              [ column, token.text ] if (column.x - token.x).abs <= gap * 0.6
            end
            notes = cells.reject { LETTER_MARKS.key?(_1.text) || CHECK_MARKS.include?(_1.text) }.map(&:text).join(" ").squish
            # A wide gap inside the name column splits the job ("Spark plugs") from a version it's
            # for ("Except SKYACTIV-G 2.5T"), as Mazda prints them.
            # A version printed on a line of its own starts well right of where job names start.
            label, sublabel = names.slice_when { |a, b| b.x - a.x > gap * 2.2 + a.text.length * 3 }.to_a.then { |parts| [ parts.first, parts.drop(1).flatten ] }
            label, sublabel = [], names if names.any? && names.first.x > label_start + gap * 3
            { y: line.first.y, label: Array(label).map(&:text).join(" ").squish,
              sublabel: sublabel.map(&:text).join(" ").gsub(/‐\s+/, "").squish, marks:, notes: }
          end
          gaps = parsed.each_cons(2).map { |a, b| a[:y] - b[:y] }.select(&:positive?).sort
          height = gaps[gaps.size / 2] || 10 # a typical line

          named = []
          parsed.each do |line|
            next if line[:label].blank?
            # A name wrapped onto a second line, unless that line has marks of its own and the row already
            # had some: then it's the next job, printed in pieces (Mitsubishi's "Inspect and … adjust valve").
            wrapped = named.any? && line[:label].match?(/\A[a-z(]/) && !(line[:marks].any? && named.last[:lines].any? { _1[:marks].any? })
            if wrapped
              named.last[:label] += " #{line[:label]}"
              named.last[:lines] << line
            else
              named << { label: line[:label], lines: [ line ] }
            end
          end
          parsed.select { _1[:label].blank? && (_1[:marks].any? || _1[:notes].present? || _1[:sublabel].present?) }.each do |line|
            distance = ->(row) { row[:lines].map { (_1[:y] - line[:y]).abs }.min }
            owner = named.min_by(&distance)
            owner[:lines] << line if owner && distance.(owner) <= height * 1.6
          end

          rows = named.map do |row|
            lines = row[:lines].sort_by { -_1[:y] }
            Row.new(label: row[:label], marks: lines.flat_map { _1[:marks] }, notes: note_groups(lines), page:, conditions:)
          end
          share_check_marks(rows, named, height)
        end

        # GM marks a group of lines once ("Rotate tires…", "Check engine oil level…", "Change engine oil
        # and filter, if needed." share one set of checks), so a line with no marks or footnote of its own
        # takes the check marks of the line right next to it.
        def share_check_marks(rows, named, height)
          ys = named.map { |row| row[:lines].map { _1[:y] } }
          rows.each_with_index.map do |row, i|
            next row if row.marks.any? || row.notes.any? { _1[1].present? } || row.label.match?(/\(\d{1,2}\)\s*\z/)
            neighbor = [ i - 1, i + 1 ].select { _1.between?(0, rows.size - 1) }.find do |j|
              rows[j].marks.any? && rows[j].marks.all? { |_, mark| CHECK_MARKS.include?(mark) } &&
                ys[i].product(ys[j]).map { |a, b| (a - b).abs }.min <= height * 1.2
            end
            neighbor ? row.with(marks: rows[neighbor].marks) : row
          end
        end

        # A row's notes as [[the version it's for, the note]]: lines run together until a line names a
        # different version ("SKYACTIV-G 2.5 T" … "Except SKYACTIV-G 2.5T").
        def note_groups(lines)
          lines.each_with_object([]) do |line, groups|
            next if line[:notes].blank? && line[:sublabel].blank?
            if groups.empty? || (line[:sublabel].present? && groups.last[0].present? && groups.last[1].present?)
              groups << [ line[:sublabel], line[:notes] ]
            else
              groups.last[0] = [ groups.last[0], line[:sublabel] ].compact_blank.join(" ")
              groups.last[1] = [ groups.last[1], line[:notes] ].compact_blank.join(" ")
            end
          end
        end

        def key(label) = label.downcase.gsub(/[^a-z ]/, "").squish

        # "Except SKY‐ ACTIV-G" reads "Except SKYACTIV-G"; "See NOTE (6)" isn't a version.
        def version(text) = text.to_s.gsub(/‐\s*/, "").gsub(/\b(see\s+)?note\s*\(\d+\)/i, "").squish.presence

        def row_items(row, months_at)
          label = row.label.sub(/\A\d+\s+/, "").sub(/[\s*#]*(\*\d+|\(\d+\)|\d)+\s*\z/, "").squish # numbering and footnotes
          return [] if label.blank?

          from_notes = row.notes.filter_map do |version, note|
            next if note.blank?
            found = Sentences.interval(note) or next
            { "action" => Sentences.action(note) || Sentences.action(label) || "replace", "applies_to" => version(version) }.merge(found)
          end
          # A footnote like "Or every two years, whichever comes first." adds a time limit to the marks.
          extra_months = row.notes.filter_map { |_, note| Sentences.interval(note.to_s)&.then { _1["interval_months"] if _1["interval_miles"].nil? } }.first
          marked = mark_items(label, row.marks, months_at).map { |item| extra_months ? item.merge("interval_months" => item["interval_months"] || extra_months) : item }
          from_notes = [] if marked.any? && extra_months
          (marked + from_notes).map do |item|
            { "name" => label, "conditions" => row.conditions, "page" => row.page, "first_due_miles" => nil, "applies_to" => nil }.merge(item)
          end
        end

        # One item per action marked in the row (a job can be inspected some years and replaced others).
        # A row naming several jobs with check marks ("Rotate tires … Change engine oil and filter", GM)
        # becomes one item per job.
        def mark_items(label, marks, months_at)
          return [] if marks.empty?

          marks.group_by { |_, mark| LETTER_MARKS[mark] || Sentences.action(label) || "other" }.flat_map do |action, marked|
            miles = marked.map { |column, _| column.miles }.uniq.sort
            interval = miles.each_cons(2).map { |a, b| b - a }.min || miles.first
            item = { "action" => action, "interval_miles" => interval, "interval_months" => months_at[interval],
                     "first_due_miles" => (miles.first if miles.first != interval) }
            jobs = label.split(/(?<=\.)\s+(?=[A-Z])/).select { Sentences.action(_1) }
            next [ item ] if jobs.size < 2 || LETTER_MARKS.key?(marked.first.last)
            jobs.filter_map do |job|
              item.merge("action" => Sentences.action(job), "name" => job.sub(/[.,]?\s*(if needed\.?)?\z/i, "")) unless Sentences.action(job) == "inspect"
            end
          end
        end
    end
  end
end
