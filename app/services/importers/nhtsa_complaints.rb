module Importers
  # Loads NHTSA's owner complaints file (FLAT_CMPL.txt: tab-separated, 51 columns, no header) as counts
  # per make, model, model year and part. Only car and failure fields are read; names, cities, dealer
  # details and complaint stories are skipped and never stored.
  #
  # https://www.nhtsa.gov/nhtsa-datasets-and-apis#complaints
  class NhtsaComplaints
    # 0-based positions from CMPL.txt
    ODINO, MAKE, MODEL, YEAR, CRASH, FIRE, COMPONENT, MILES, PRODUCT, TOWED = 1, 3, 4, 5, 6, 8, 11, 17, 45, 48

    Counts = Struct.new(:odinos, :towed, :crashes, :fires, :with_miles, :miles_total) do
      def self.empty = new(Set.new, 0, 0, 0, 0, 0)
    end

    def initialize(path, first_model_year: 2000)
      @path = path
      @first_model_year = first_model_year
    end

    # Replaces all counts; returns the number of car/part rows written.
    def call
      counts = Hash.new { |hash, key| hash[key] = Counts.empty }
      File.foreach(@path, chomp: true, encoding: "bom|utf-8", invalid: :replace, undef: :replace) do |line|
        fields = line.split("\t", -1)
        next unless fields[PRODUCT] == "V"
        year = fields[YEAR].to_i
        next unless year >= @first_model_year && year <= Date.current.year + 1
        slug = NhtsaComponent.category_slug(fields[COMPONENT]) or next

        entry = counts[[ VehicleName.make_key(fields[MAKE]), VehicleName.model_key(fields[MODEL]), year, slug ]]
        # A complaint naming two parts in one category counts once.
        next unless entry.odinos.add?(fields[ODINO])
        entry.towed += 1 if fields[TOWED] == "Y"
        entry.crashes += 1 if fields[CRASH] == "Y"
        entry.fires += 1 if fields[FIRE] == "Y"
        miles = fields[MILES].to_i
        if miles.between?(1, 400_000)
          entry.with_miles += 1
          entry.miles_total += miles
        end
      end
      write(counts)
    end

    private
      def write(counts)
        now = Time.current
        rows = counts.map do |(make_key, model_key, model_year, category_slug), entry|
          { make_key:, model_key:, model_year:, category_slug:, complaints: entry.odinos.size, towed: entry.towed,
            crashes: entry.crashes, fires: entry.fires, with_miles: entry.with_miles, miles_total: entry.miles_total,
            created_at: now, updated_at: now }
        end
        ComplaintCount.transaction do
          ComplaintCount.delete_all
          rows.each_slice(10_000) { |slice| ComplaintCount.insert_all!(slice) }
        end
        rows.size
      end
  end
end
