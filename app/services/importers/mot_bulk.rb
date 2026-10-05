module Importers
  # Loads the DVSA "Anonymised MOT tests and results" files. Each file is read by its header row, so
  # both the older pipe-separated layout and the 2023+ comma-separated one work:
  #
  #   results  test_id, vehicle_id, test_date or completed_date, test_class_id, test_type, test_result,
  #            test_mileage, make, model, fuel_type, cylinder_capacity, first_use_date, ...
  #   items    test_id, rfr_id, rfr_type_code, dangerous_mark, ...   (the "failure item" files)
  #   details  rfr_id, rfr_desc and/or rfr_advisory_text, ...         (item_detail, from the lookup tables)
  #   groups   test_item_id, test_class_id, item_name                   (item_group, optional: names the part)
  #
  # Each file is streamed into a temporary table with COPY and turned into vehicles, inspections,
  # defect phrases and defects with set-based SQL, in its own transaction. Details load first, then
  # results, then items, because an item only counts once its test is loaded. Loaded files are
  # recorded in import_runs and skipped next time. Only normal tests (NT) of cars (class 4) are kept.
  #
  # https://www.data.gov.uk/dataset/c63fca52-ae4c-4b75-bab5-8b4735e1a4c9/anonymised-mot-tests-and-results
  class MotBulk
    class FormatError < StandardError; end

    SOURCE = "mot"
    DEMO_SOURCE = "mot_demo"

    # Columns the demo generator and tests write. Real files may have more.
    COLUMNS = {
      results: %w[test_id vehicle_id test_date test_class_id test_type test_result test_mileage postcode_area
                  make model colour fuel_type cylinder_capacity first_use_date],
      items: %w[test_id rfr_id rfr_type_code location_id dangerous_mark],
      details: %w[rfr_id test_class_id test_item_id minor_item rfr_desc rfr_loc_marker rfr_insp_manual_desc
                  rfr_advisory_text test_item_set_section_id]
    }.freeze

    REQUIRED = {
      groups: %w[test_item_id item_name],
      details: %w[rfr_id],
      results: %w[test_id vehicle_id test_result test_mileage make model],
      items: %w[test_id rfr_id rfr_type_code]
    }.freeze

    # The inspector's full sentence says the most; rfr_desc alone is often a fragment like "missing".
    PHRASE_COLUMNS = %w[rfr_insp_manual_desc rfr_desc rfr_advisory_text].freeze

    Summary = Data.define(:files, :skipped, :vehicles, :inspections, :phrases, :defects) do
      def self.empty = new(files: 0, skipped: 0, vehicles: 0, inspections: 0, phrases: 0, defects: 0)
      def +(other) = self.class.new(**to_h.merge(other.to_h) { |_, a, b| a + b })
    end

    # Pass one path or a list for each kind. source: "mot" for real downloads, DEMO_SOURCE for demo files.
    # on_file is called with (kind, path, counts) after each file, for progress output.
    def initialize(results: [], items: [], details: [], groups: nil, source: SOURCE, connection: ActiveRecord::Base.connection, on_file: nil)
      @files = { details: Array(details), results: Array(results), items: Array(items) }.transform_values { |paths| paths.compact.map(&:to_s) }
      @groups = groups&.to_s
      @source = source
      @connection = connection
      @on_file = on_file
    end

    def call
      @files.sum(Summary.empty) do |kind, paths|
        paths.sum(Summary.empty) { |path| load_file(kind, path) }
      end
    end

    private
      def load_file(kind, path)
        if ImportRun.loaded?(source: @source, kind:, path:)
          @on_file&.call(kind, path, :skipped)
          return Summary.empty.with(skipped: 1)
        end

        counts = @connection.transaction do
          @columns = stage(kind, path)
          counts = send("load_#{kind}")
          # An items file that matches no loaded tests stays unrecorded, so it can be loaded again later.
          ImportRun.record!(source: @source, kind:, path:, counts:) unless kind == :items && counts[:defects].zero?
          counts
        end
        @on_file&.call(kind, path, counts)
        Summary.empty.with(files: 1, **counts)
      end

      def stage(kind, path, table: "mot_stage")
        columns, delimiter = read_header(path)
        missing = REQUIRED.fetch(kind) - columns
        raise FormatError, "#{File.basename(path)} is missing #{missing.join(", ")} (has #{columns.join(", ")})" if missing.any?
        if kind == :results && (columns & %w[test_date completed_date]).empty?
          raise FormatError, "#{File.basename(path)} needs test_date or completed_date"
        end

        execute "DROP TABLE IF EXISTS #{table}"
        execute "CREATE TEMP TABLE #{table} (#{columns.map { |column| "#{column} text" }.join(", ")}) ON COMMIT DROP"
        raw = @connection.raw_connection
        # DVSA's comma files escape quotes with a backslash ("12\""); its pipe files never quote at all,
        # but have bare quotes inside text (beam "kick up"), so quoting is switched off for them.
        quoting = delimiter == "," ? "ESCAPE E'\\\\'" : "QUOTE E'\\x01'"
        raw.copy_data("COPY #{table} FROM STDIN WITH (FORMAT csv, DELIMITER #{quote(delimiter)}, #{quoting}, HEADER true)") do
          File.open(path, "rb") { |file| while (chunk = file.read(1 << 20)) do raw.put_copy_data(chunk) end }
        end
        # DVSA files repeat the header row partway through; drop the copies.
        execute "DELETE FROM #{table} WHERE #{columns.first} = #{quote(columns.first)}"
        analyze table
        columns
      end

      def read_header(path)
        line = File.open(path, "r:bom|utf-8", &:gets).to_s
        delimiter = line.count("|") > line.count(",") ? "|" : ","
        columns = line.strip.split(delimiter).map { |name| name.strip.downcase.gsub(/[^a-z0-9]+/, "_").delete_suffix("_") }
        [ columns, delimiter ]
      end

      def column?(name) = @columns.include?(name)
      def column_or_null(name) = column?(name) ? "s.#{name}" : "NULL"

      def load_details
        text_columns = PHRASE_COLUMNS.select { |name| column?(name) }
        raise FormatError, "details file needs one of #{PHRASE_COLUMNS.join(", ")}" if text_columns.empty?
        text = "coalesce(#{text_columns.map { |name| "nullif(trim(s.#{name}), '')" }.join(", ")})"
        cars_only = column?("test_class_id") ? "AND (s.test_class_id IN ('4', '') OR s.test_class_id IS NULL)" : ""
        from = "mot_stage s"

        # Prefix the part's name ("Suspension component: ...") when the item groups are available.
        if @groups && column?("test_item_id")
          detail_columns = @columns
          group_columns = stage(:groups, @groups, table: "mot_groups")
          @columns = detail_columns
          if (%w[test_item_id item_name] - group_columns).empty?
            class_match = column?("test_class_id") && group_columns.include?("test_class_id") ? "AND g.test_class_id = s.test_class_id" : ""
            from = "mot_stage s LEFT JOIN mot_groups g ON g.test_item_id = s.test_item_id #{class_match}"
            text = "coalesce(nullif(trim(g.item_name), '') || ': ', '') || #{text}"
          end
        end

        # A phrase whose wording changes is sent back to be categorized again.
        phrases = execute(<<~SQL).cmd_tuples
          INSERT INTO defect_phrases (source, external_id, text)
          SELECT DISTINCT ON (s.rfr_id) #{quote(@source)}, s.rfr_id, #{text}
          FROM #{from}
          WHERE #{text} IS NOT NULL #{cars_only}
          ORDER BY s.rfr_id
          ON CONFLICT (source, external_id) DO UPDATE
            SET text = EXCLUDED.text, defect_category_id = NULL, categorized_at = NULL, updated_at = now()
            WHERE defect_phrases.text IS DISTINCT FROM EXCLUDED.text
        SQL
        { phrases: }
      end

      def load_results
        tested_on = "left(#{column?("test_date") ? "nullif(s.test_date, '')" : "NULL"}, 10)"
        tested_on = "coalesce(#{tested_on}, left(nullif(s.completed_date, ''), 10))" if column?("completed_date")
        cars = [ "s.test_result IN ('P', 'F', 'PRS')" ]
        cars << "s.test_class_id = '4'" if column?("test_class_id")
        cars << "s.test_type = 'NT'" if column?("test_type")
        cars = cars.join(" AND ")

        stage_model_keys
        vehicles = execute(<<~SQL).cmd_tuples
          INSERT INTO vehicles (source, external_id, country, make, model, make_key, model_key, engine_key,
                                fuel_type, engine_cc, first_used_on)
          SELECT DISTINCT ON (s.vehicle_id)
            #{quote(@source)}, s.vehicle_id, 'GB', trim(s.make), trim(s.model),
            #{make_key_sql("s.make")}, mk.model_key,
            #{engine_key_sql(column_or_null("cylinder_capacity"), column_or_null("fuel_type"))},
            nullif(trim(#{column_or_null("fuel_type")}), ''),
            nullif(#{column_or_null("cylinder_capacity")}, '')::numeric::int,
            left(nullif(#{column_or_null("first_use_date")}, ''), 10)::date
          FROM mot_stage s
          JOIN mot_model_keys mk ON mk.model = trim(s.model)
          WHERE #{cars} AND nullif(trim(s.make), '') IS NOT NULL AND nullif(trim(s.model), '') IS NOT NULL
          ORDER BY s.vehicle_id, #{tested_on} DESC
          ON CONFLICT (source, external_id) DO NOTHING
        SQL
        analyze "vehicles"

        inspections = execute(<<~SQL).cmd_tuples
          INSERT INTO inspections (vehicle_id, source, external_id, inspected_on, mileage, result)
          SELECT v.id, #{quote(@source)}, s.test_id, #{tested_on}::date, nullif(s.test_mileage, '')::numeric::int,
                 CASE s.test_result WHEN 'P' THEN 'pass' WHEN 'PRS' THEN 'pass_after_repair' ELSE 'fail' END
          FROM mot_stage s
          JOIN vehicles v ON v.source = #{quote(@source)} AND v.external_id = s.vehicle_id
          WHERE #{cars} AND #{tested_on} IS NOT NULL
          ON CONFLICT (source, external_id) DO NOTHING
        SQL
        analyze "inspections"
        { vehicles:, inspections: }
      end

      def load_items
        # Items can arrive before their wording; they're named later by a details file.
        phrases = execute(<<~SQL).cmd_tuples
          INSERT INTO defect_phrases (source, external_id, text)
          SELECT #{quote(@source)}, ids.rfr_id, 'MOT item ' || ids.rfr_id
          FROM (SELECT DISTINCT rfr_id FROM mot_stage WHERE rfr_id <> '') ids
          ON CONFLICT (source, external_id) DO NOTHING
        SQL
        analyze "defect_phrases"

        dangerous = column?("dangerous_mark") ? "s.dangerous_mark = 'D'" : "false"
        defects = execute(<<~SQL).cmd_tuples
          INSERT INTO defects (inspection_id, defect_phrase_id, kind, severity)
          SELECT i.id, p.id,
                 CASE WHEN s.rfr_type_code IN ('A', 'M') THEN 'advisory' ELSE 'fail' END,
                 CASE WHEN #{dangerous} THEN 'dangerous'
                      WHEN s.rfr_type_code IN ('F', 'P') THEN 'major'
                      WHEN s.rfr_type_code = 'M' THEN 'minor'
                      ELSE 'advisory' END
          FROM mot_stage s
          JOIN inspections i ON i.source = #{quote(@source)} AND i.external_id = s.test_id
          JOIN defect_phrases p ON p.source = #{quote(@source)} AND p.external_id = s.rfr_id
        SQL
        { phrases:, defects: }
      end

      # Same rules as VehicleName.make_key.
      def make_key_sql(column)
        cleaned = "regexp_replace(upper(trim(#{column})), '\\s+', ' ', 'g')"
        cases = VehicleName::MAKE_ALIASES.map { |from, to| "WHEN #{quote(from)} THEN #{quote(to)}" }.join(" ")
        "CASE #{cleaned} #{cases} ELSE #{cleaned} END"
      end

      # Model keys come from VehicleName.model_key (one rule for every source), computed once per
      # distinct model name in the file and joined in.
      def stage_model_keys
        execute "DROP TABLE IF EXISTS mot_model_keys"
        execute "CREATE TEMP TABLE mot_model_keys (model text PRIMARY KEY, model_key text NOT NULL) ON COMMIT DROP"
        models = @connection.select_values("SELECT DISTINCT trim(model) FROM mot_stage WHERE nullif(trim(model), '') IS NOT NULL")
        models.each_slice(1_000) do |slice|
          values = slice.map { |model| "(#{quote(model)}, #{quote(VehicleName.model_key(model))})" }.join(", ")
          execute "INSERT INTO mot_model_keys (model, model_key) VALUES #{values}"
        end
      end

      # Same rules as VehicleName.engine_key.
      def engine_key_sql(cc_column, fuel_column)
        fuel_cases = VehicleName::FUEL_CODES.map { |from, to| "WHEN #{quote(from)} THEN #{quote(to)}" }.join(" ")
        fuel = "(CASE upper(trim(#{fuel_column})) #{fuel_cases} ELSE NULL END)"
        cc = "nullif(#{cc_column}, '')::numeric"
        "CASE WHEN #{fuel} = 'E' THEN 'EV' " \
          "WHEN #{cc} > 0 THEN to_char(round(#{cc} / 1000.0, 1), 'FM990.0') || coalesce('-' || #{fuel}, '') " \
          "ELSE NULL END"
      end

      # Fresh statistics after each bulk step. Without them Postgres plans joins as if a table were still
      # empty and re-scans millions of rows once per car, which never finishes.
      def analyze(table) = execute("ANALYZE #{table}")

      def quote(value) = @connection.quote(value)
      def execute(sql) = @connection.raw_connection.exec(sql)
  end
end
