module MaintenanceGuides
  module Rules
    # Reads intervals written out in words: "Replace every 64,000 km (40,000 miles).", "Rotate every
    # 12,000 km (7,500 miles).", "replace the brake fluid every 3 years", "Replace at first 192,000 km
    # (120,000 miles) or 10 years; after that, every 96,000 km (60,000 miles) or 5 years."
    module Sentences
      module_function

      ACTIONS = { /\A\W*(replace|change|drain)\b/i => "replace", /\A\W*rotate\b/i => "rotate", /\A\W*(inspect|check)\b/i => "inspect" }.freeze
      MILES = /([\d,]+(?:\.\d+)?)\s*(k)?\s*(?:miles|mi)\b/i # "40,000 miles", "40K miles"
      MONTHS = /(\d+)\s*months?\b/i
      YEARS = /(\d+)\s*years?\b/i

      # The action a sentence or row label starts with ("replace", "rotate", "inspect"), or nil.
      def action(text)
        ACTIONS.find { |pattern, _| text.match?(pattern) }&.last
      end

      # { "interval_miles", "interval_months", "first_due_miles" } from one sentence, or nil when it states
      # no interval. With "at first … after that, every …" the second part is the interval.
      def interval(text)
        return if text.blank?
        first, after = digits(text).split(/after that,?|,?\s*then\b/i, 2)
        repeat = after || first
        return unless repeat.match?(/\bevery\b|max(imum)? interval|annually|\byearly\b/i) || after

        miles = miles(repeat)
        months = repeat[MONTHS, 1]&.to_i || repeat[YEARS, 1]&.then { _1.to_i * 12 } || (12 if repeat.match?(/annually|\byearly\b/i))
        return unless miles || months

        { "interval_miles" => miles, "interval_months" => months, "first_due_miles" => (miles(first) if after) }
      end

      # Sentences anywhere in a page's text that name a job and how often: "Independent of the Maintenance
      # Minder information, replace the brake fluid every 3 years."
      def items(text, page:)
        digits(text).gsub(/\s+/, " ").split(/(?<=[.;])\s+/).filter_map do |sentence|
          # The job starts at the clause that names it ("Independent of …, replace the brake fluid …").
          job = sentence[/[^.;,]*?\b(replace(ment)?|change|rotat(e|ion))\b.*/i]&.strip or next
          # "Replace … if …" is conditional work; "every 6,250 miles … or if tread depth …" isn't.
          next if sentence.split(/\bevery\b/i, 2).first.match?(/\bif\b(?! needed)|severe|towing|dusty/i)
          found = interval(job) or next
          before = job.split(/\bevery\b/i, 2).first
          # "Brake fluid health check every 4 years (replace if necessary)" is a check.
          kind = action(job) || (before.match?(/\bcheck\b/i) && "inspect") || (job.match?(/rotation/i) ? "rotate" : "replace")
          { "name" => job.sub(/\A\W+/, "").sub(/\s*every\b.*/i, "").strip, "action" => kind, "conditions" => "normal",
            "applies_to" => nil, "page" => page }.merge(found)
        end
      end

      def number(text) = text && (text.delete(",").to_f).round

      def miles(text)
        found = text.match(MILES) or return
        number(found[1]) * (found[2] ? 1000 : 1)
      end

      WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve].each_with_index.to_h.freeze

      # "every five years" reads as "every 5 years".
      def digits(text) = text.gsub(/\b(#{WORDS.keys.join("|")})\b(?=\s+(years?|months?))/i) { WORDS[$1.downcase].to_s }
    end
  end
end
