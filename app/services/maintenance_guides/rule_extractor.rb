module MaintenanceGuides
  # Reads a guide's schedule with plain rules, no model: in seconds, the same way every time, and with
  # nothing to install. Three layouts are understood:
  #
  #   - mileage checklists, one per service mileage (Toyota, Lexus): Rules::ChecklistItems;
  #   - grids, a column per mileage and a mark where a job is due (Nissan, Infiniti, Mazda, Subaru,
  #     Hyundai, Chevrolet, GMC, Buick, Cadillac): Rules::Grid;
  #   - sentences, "replace the brake fluid every 3 years" (Honda and Acura, whose Maintenance Minder
  #     otherwise decides timing from how the car is driven): Rules::Sentences.
  #
  # Returns an extraction in the shape ClaudeExtractor gives, or nil when nothing could be read.
  class RuleExtractor
    MODEL = "rules".freeze
    MIN_CHECKLISTS = 4 # fewer means the guide isn't laid out as checklists
    MAX_SENTENCE_PAGES = 40 # sentences are only read from short guides; a whole owner's manual says too much

    def initialize(vpic: Nhtsa::Vpic.new)
      @vpic = vpic
    end

    def extract(pdf_path, guide: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      text = PdfText.new(pdf_path)
      found = checklists(text) || bundles(text) || grid(pdf_path, text) || sentences(text)
      return unless found

      items = guide&.kind.in?(%i[all_models_booklet nhtsa_filing]) ? for_model(found[:items], guide) : found[:items]
      electric = guide && VehicleName.electric?(make_key: VehicleName.make_key(guide.make), engine_key: nil)
      { "items" => items, "layout" => found[:layout], "checklists" => found[:pieces], "pages" => found[:pages], "electric" => electric,
        "model" => MODEL, "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1),
        "prompt_tokens" => 0, "output_tokens" => 0 }
    end

    private
      def checklists(text)
        pages = text.schedule_pages
        lists = Checklists.from(pages)
        return if lists.size < MIN_CHECKLISTS

        readings = lists.map { |checklist| [ checklist, Rules::ChecklistItems.from(checklist.text) ] }
        { items: Intervals.from(readings), layout: "mileage_checklists", pages: pages.map(&:number),
          pieces: readings.map { |checklist, items| { "miles" => checklist.miles, "page" => checklist.page, "items" => items } } }
      end

      def bundles(text)
        items = Rules::Bundles.items(text.page_texts)
        return unless items.any? { _1["action"] == "replace" }

        { items:, layout: "bundles", pages: items.map { _1["page"] }.uniq.sort, pieces: [] }
      end

      def grid(pdf_path, text)
        grid = Rules::Grid.new(pdf_path, texts: text.page_texts)
        items = grid.items
        return unless items.any? { _1["action"] == "replace" }

        { items:, layout: "grid", pages: grid.pages, pieces: grid.pages.map { { "page" => _1 } } }
      end

      # Short guides are read whole. In a whole owner's manual only the maintenance section counts (Tesla:
      # "Maintenance Service Intervals"), since the rest mentions replacing things for other reasons.
      MAINTENANCE_SECTION = /maintenance (service )?intervals|maintenance schedule|service intervals/i

      def sentences(text)
        pages = text.page_texts.each_with_index.map { |page_text, index| [ page_text, index + 1 ] }
        if text.page_count > MAX_SENTENCE_PAGES
          starts = pages.select { |page_text, _| page_text.match?(MAINTENANCE_SECTION) }.map(&:last)
          pages = pages.select { |_, number| starts.any? { number.between?(_1, _1 + 1) } }
        end
        items = pages.flat_map do |page_text, number|
          section = text.page_count > MAX_SENTENCE_PAGES ? page_text[(page_text =~ MAINTENANCE_SECTION || 0)..] : page_text
          Rules::Sentences.items(section, page: number)
        end
        return if items.empty?

        { items: agreed(items), layout: "sentences", pages: items.map { _1["page"] }.uniq, pieces: [] }
      end

      # A manual for several models can repeat a job with different intervals and no label saying which
      # model each is for (Tesla's lists for S/X and 3/Y). Takes the interval most of them give, or the
      # shorter one on a tie, so upkeep isn't understated.
      def agreed(items)
        items.group_by { |item| Intervals.group_key(item) }.map do |_, same|
          counts = same.map { _1.values_at("interval_miles", "interval_months") }.tally
          best = counts.max_by { |(miles, months), count| [ count, -(miles || Float::INFINITY), -(months || Float::INFINITY) ] }.first
          same.find { _1.values_at("interval_miles", "interval_months") == best }
        end
      end

      # A booklet or filing for every model marks some jobs for certain models only: in a note on the job
      # ("Timing belt (WRX STI)", Subaru) or in a column of models ("A3, S3, A4, S4, A5", "All vehicles
      # except RS7 and A8 LWB", Audi). Keeps what applies to this model or to every model. Only names the
      # maker sold that year (from NHTSA) count as models, so "(MT only)" or "6 Cyl: 3.6L engines only"
      # isn't mistaken for one.
      def for_model(items, guide)
        sold = (@vpic.models(make: guide.make, model_year: guide.model_year).map { squash(_1) } + %w[hybrid sti]).uniq.sort_by { -_1.length }
        ours = squash(guide.model)
        kept = items.reject do |item|
          # The first note decides: "Engine coolant (engine side), (inverter assembly side - Hybrid)" is for
          # every car, with an extra part for the hybrid.
          notes = [ item["name"].to_s[/\(([^)]*)\)/, 1], *item["applies_to"].to_s.split(/\s*;\s*/) ].compact_blank
          notes.any? { |note| !for_us?(note, sold, ours) }
        end
        # Once a job is known to be for this car, its list of models says nothing; a version ("DSG", "3.6L
        # engines only") still does.
        kept.map do |item|
          versions = item["applies_to"].to_s.split(/\s*;\s*/).reject { |note| note.match?(/\Aall\s+(vehicles|models)/i) || names_models?(note, sold) }
          item.merge("applies_to" => versions.join("; ").presence)
        end
      end

      def names_models?(note, sold) = note.split(/\s*(?:,|&|\band\b|\/)\s*/).any? { |entry| sold.any? { squash(entry).start_with?(_1) } }

      # Whether a note listing models covers ours. A note naming no model covers every car.
      def for_us?(note, sold, ours)
        excepting = note.match?(/\A\s*(all\s+(vehicles|models)\s+)?except\b/i)
        entries = note.sub(/\A\s*(all\s+(vehicles|models)\s+)?except\s+/i, "").split(/\s*(?:,|;|&|\band\b|\/)\s*/)
        named = entries.filter_map { |entry| sold.find { squash(entry).start_with?(_1) } }
        return true if named.empty?
        mentioned = named.any? { _1 == ours || ours.start_with?(_1) && _1.length >= ours.length - 1 }
        excepting ? !mentioned : mentioned
      end

      def squash(name) = name.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end
end
