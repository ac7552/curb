module MaintenanceGuides
  # Reads guides for many cars ahead of time on a developer's machine, so buyers find their car's
  # schedule already there. Each result is saved as a file under db/seeds/maintenance_guides (committed,
  # and loaded into the database by db:seed on every machine) and into this machine's database straight away.
  #
  # Cars that fail are logged to tmp/guides/prefill_errors.jsonl and skipped. They have no seed file, so
  # the next run tries them again; cars with a seed file are skipped unless forced.
  class Prefill
    Car = Data.define(:make, :model, :model_year) do
      def to_s = "#{model_year} #{make} #{model}"
    end

    # Makes whose reading has been checked against hand-made answer keys. Results for any other make are
    # saved as "needs_review" however clean they look, so nothing unchecked reaches a report.
    VERIFIED_MAKES = %w[TOYOTA].freeze

    cattr_accessor :seed_dir, default: Rails.root.join("db/seeds/maintenance_guides")
    cattr_accessor :error_log, default: Rails.root.join("tmp/guides/prefill_errors.jsonl")

    # Each make's best-selling models (US sales, or the most-inspected models for makes without sales
    # figures), for every model year NHTSA lists them, named the way NHTSA spells them ("4Runner", "C-HR"),
    # which is close to how makers name their guides.
    def self.popular_cars(makes:, top:, years:, vpic: Nhtsa::Vpic.new)
      makes.flat_map do |make|
        make_key = VehicleName.make_key(make)
        popular = ModelSale.where(make_key:).group(:model_key).order(Arel.sql("SUM(units) DESC")).sum(:units).keys.first(top)
        popular = MakeCatalog.popular_models(make_key, "US").first(top) if popular.empty?
        years.flat_map do |year|
          listed = vpic.models(make:, model_year: year)
          popular.filter_map do |model_key|
            name = listed.find { |listed_name| VehicleName.model_key(listed_name) == model_key }
            Car.new(make: VehicleName.display_make(make_key), model: name, model_year: year) if name
          end
        end
      end
    end

    def self.seed_path(car) = Pathname(seed_dir).join(car.make.parameterize, "#{car.model_year}-#{car.model.parameterize}.json")

    # Loads one seed file into the database. Used here and by Curb::ReferenceData.
    def self.load_file(path)
      data = JSON.parse(File.read(path))
      attributes = {
        make_key: VehicleName.make_key(data["make"]), model_key: VehicleName.model_key(data["model"]),
        model_year: data["model_year"], make: data["make"], model: data["model"], status: data["status"],
        url: data["url"], title: data["title"], rows: data["rows"], problems: data["problems"],
        read_with: data["read_with"], read_at: data["read_at"]
      }
      MaintenanceGuide.upsert(attributes, unique_by: %i[make_key model_key model_year])
    end

    def initialize(finder: Finder.new, reader: Reader.new, out: $stdout)
      @finder = finder
      @reader = reader
      @out = out
    end

    # Reads each car in turn. Returns counts: ok, needs_review, not_found, failed, already_done.
    def run(cars, force: false)
      counts = Hash.new(0)
      cars.each_with_index do |car, index|
        if !force && self.class.seed_path(car).exist?
          counts[:already_done] += 1
          next
        end

        @out.print "[#{index + 1}/#{cars.size}] #{car} … "
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        guide = @finder.find(make: car.make, model: car.model, model_year: car.model_year)
        unless guide
          log_error(car, "No guide at the address we expected for this maker")
          counts[:not_found] += 1
          @out.puts "no guide found (logged)"
          next
        end

        read = @reader.read(guide)
        status = save(car, read)
        counts[status.to_sym] += 1
        @out.puts "#{status} in #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round}s, #{read.result.rows.size} items" \
                  "#{" — #{read.result.problems.join("; ")}" if read.result.problems.any?}"
      rescue ClaudeExtractor::Unavailable, Interrupt
        raise # nothing after this would work either
      rescue StandardError => e
        log_error(car, "#{e.class}: #{e.message}")
        counts[:failed] += 1
        @out.puts "failed (logged): #{e.message.truncate(120)}"
      end
      counts
    end

    # The latest logged error for each car that still has no seed file.
    def self.failures
      return [] unless File.exist?(error_log)
      File.foreach(error_log).map { |line| JSON.parse(line) }
               .group_by { |entry| entry.values_at("make", "model", "model_year") }
               .map { |_, entries| entries.last }
               .reject { |entry| seed_path(Car.new(make: entry["make"], model: entry["model"], model_year: entry["model_year"])).exist? }
    end

    private
      def save(car, read)
        path = self.class.seed_path(car)
        FileUtils.mkdir_p(path.dirname)
        status, problems = read.result.status, read.result.problems
        unless VERIFIED_MAKES.include?(VehicleName.make_key(car.make))
          status = "needs_review"
          problems += [ "#{car.make}'s guides haven't been checked against an answer key yet" ]
        end
        File.write(path, JSON.pretty_generate(
          make: car.make, model: car.model, model_year: car.model_year, status:, kind: read.guide.kind,
          url: read.guide.url, title: read.guide.title, rows: read.result.rows, problems:, layout: read.extraction["layout"],
          skipped: read.result.skipped, read_with: read.extraction["model"], read_at: Time.current.iso8601,
          checklists: read.extraction["checklists"]
        ) + "\n")
        self.class.load_file(path)
        status
      end

      def log_error(car, message)
        FileUtils.mkdir_p(File.dirname(error_log))
        File.open(error_log, "a") do |file|
          file.puts({ at: Time.current.iso8601, make: car.make, model: car.model, model_year: car.model_year, error: message }.to_json)
        end
      end
  end
end
