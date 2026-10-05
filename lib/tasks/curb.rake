namespace :curb do
  namespace :import do
    desc "Load every DVSA MOT file in one or more folders: bin/rails 'curb:import:mot_dir[results folder,items folder]'"
    task :mot_dir, %i[dir] => :environment do |_, args|
      $stdout.sync = true
      dirs = [ args[:dir], *args.extras ].compact.map { |dir| Pathname(dir) }
      abort "Usage: bin/rails 'curb:import:mot_dir[folder,another folder]'" if dirs.empty? || !dirs.all?(&:directory?)

      find = ->(pattern) { dirs.flat_map { |dir| Dir.glob(dir.join("**", pattern).to_s, File::FNM_CASEFOLD) }.sort }
      files = { results: find.("*test_result*.csv"), items: find.("*test_item*.csv"), details: find.("*item_detail*.csv") }
      groups = find.("*item_group*.csv").first
      files.each { |kind, paths| puts "#{kind.to_s.ljust(8)} #{paths.size} file(s)" }

      if files[:results].empty? && files[:details].empty?
        puts <<~TEXT

          No test result files found (names with "test_result"). Failure items only count once the tests
          they belong to are loaded, so nothing was imported. Add "MOT testing data results" for the same
          year, and the "MOT testing data lookup tables" for defect wording, from:
          https://www.data.gov.uk/dataset/c63fca52-ae4c-4b75-bab5-8b4735e1a4c9/anonymised-mot-tests-and-results
        TEXT
        next
      end
      warn "No item_detail file found: defects will be named 'MOT item <id>' until one is loaded." if files[:details].empty?

      Rake::Task["curb:clear_demo"].invoke if files[:results].any? && Vehicle.exists?(source: Importers::MotBulk::DEMO_SOURCE)

      started = Time.current
      report = lambda do |kind, path, counts|
        detail = counts == :skipped ? "already loaded, skipped" : counts.map { |key, value| "#{value} #{key}" }.join(", ")
        puts "#{Time.current.strftime("%H:%M:%S")}  #{kind.to_s.ljust(8)} #{File.basename(path)}: #{detail}"
      end
      summary = Importers::MotBulk.new(details: files[:details], results: files[:results], groups:, on_file: report).call
      if files[:items].any?
        puts "#{Time.current.strftime("%H:%M:%S")}  dropping defect indexes for the bulk load (rebuilt afterwards)"
        Importers::DefectIndexes.without_indexes do
          summary += Importers::MotBulk.new(items: files[:items], on_file: report).call
          puts "#{Time.current.strftime("%H:%M:%S")}  rebuilding defect indexes"
        end
      end
      puts "Done in #{(Time.current - started).round}s: #{summary.to_h}"
      puts "Next: bin/rails curb:categorize (sorts defect wording into categories, then rebuilds the rate tables)"
    end

    desc "Load NHTSA owner complaints and service bulletins from a folder: bin/rails 'curb:import:nhtsa[NHTSA data]'"
    task :nhtsa, %i[dir] => :environment do |_, args|
      $stdout.sync = true
      dir = Pathname(args[:dir].to_s)
      abort "Usage: bin/rails 'curb:import:nhtsa[folder]'" unless dir.directory?
      complaints = Dir.glob(dir.join("**", "FLAT_CMPL*.txt").to_s).first
      bulletins = Dir.glob(dir.join("**", "MFR_COMMS_RECEIVED_*.csv").to_s).sort
      if complaints
        puts "Complaints: #{Importers::NhtsaComplaints.new(complaints).call} car/part rows"
      else
        warn "No FLAT_CMPL.txt found: download FLAT_CMPL.zip from https://www.nhtsa.gov/nhtsa-datasets-and-apis#complaints"
      end
      puts "Bulletins: #{Importers::NhtsaBulletins.new(bulletins).call} car/year rows" if bulletins.any?
    end

    desc "Load specific DVSA MOT files: bin/rails 'curb:import:mot[test_result.csv,test_item.csv,item_detail.csv]'"
    task :mot, %i[results items details] => :environment do |_, args|
      abort "Usage: bin/rails 'curb:import:mot[results_file,items_file,details_file]'" unless args[:results] && args[:items]
      summary = Importers::MotBulk.new(results: args[:results], items: args[:items], details: args[:details]).call
      puts "Loaded #{summary.to_h}"
      puts "Next: bin/rails curb:categorize (then the rate tables rebuild)"
    end
  end

  desc "Categorize new defect phrases (Claude if ANTHROPIC_API_KEY is set, keywords otherwise), then rebuild rates"
  task categorize: :environment do
    CategorizeDefectPhrasesJob.perform_now(refresh: false)
    DefectRate.refresh_all!
    puts "Categorized. #{DefectPhrase.where.not(categorized_at: nil).count} phrases, #{DefectRate.count} rate rows."
    waiting = DefectPhrase.where(categorized_at: nil).where("text LIKE ?", DefectPhrase::PLACEHOLDER).count
    puts "#{waiting} defect codes have no wording yet. Load the MOT lookup tables (item_detail) to sort them." if waiting.positive?
  end

  desc "Recompute every stored vehicle's model key after changing VehicleName.model_key, then rebuild rates"
  task rekey_models: :environment do
    $stdout.sync = true
    conn = ActiveRecord::Base.connection
    models = conn.select_rows("SELECT DISTINCT model, model_key FROM vehicles")
    changed = models.filter_map { |model, key| [ model, VehicleName.model_key(model) ] if VehicleName.model_key(model) != key }.uniq
    puts "#{changed.size} model names change key"
    conn.transaction do
      conn.execute "CREATE TEMP TABLE model_rekeys (model text PRIMARY KEY, model_key text NOT NULL) ON COMMIT DROP"
      changed.each_slice(1_000) do |slice|
        conn.execute "INSERT INTO model_rekeys VALUES #{slice.map { |m, k| "(#{conn.quote(m)}, #{conn.quote(k)})" }.join(", ")}"
      end
      updated = conn.update("UPDATE vehicles v SET model_key = r.model_key FROM model_rekeys r WHERE v.model = r.model AND v.model_key <> r.model_key")
      puts "#{updated} vehicles re-keyed"
    end
    conn.execute "SET work_mem = '512MB'"
    DefectRate::VIEWS.each do |view|
      started = Time.current
      Scenic.database.refresh_materialized_view(view, concurrently: false, cascade: false)
      puts "refreshed #{view} (#{(Time.current - started).round}s)"
    end
  end

  desc "Tag service bulletins with known failure themes (runs automatically on import)"
  task tag_bulletins: :environment do
    puts "Tagged #{BulletinTheme.tag_all!} bulletin rows"
    ModelProfile.clear_cache
  end

  desc "Rebuild the defect-rate materialized views (includes model weak-spot profiles, about 10 minutes on a full year)"
  task refresh_rates: :environment do
    DefectRate.refresh_all!
    puts "#{InspectionCell.count} cells, #{DefectRate.count} rate rows, #{DefectBaseline.count} baselines"
  end

  desc "Remove the generated demo inspections (run before loading real MOT files)"
  task clear_demo: :environment do
    source = Importers::MotBulk::DEMO_SOURCE
    ActiveRecord::Base.transaction do
      inspections = Inspection.where(source:)
      Defect.where(inspection_id: inspections.select(:id)).delete_all
      inspections.delete_all
      Vehicle.where(source:).delete_all
      DefectPhrase.where(source:).where.missing(:defects).delete_all
      ImportRun.where(source:).delete_all
    end
    DefectRate.refresh_all!(concurrently: false)
    puts "Demo data removed."
  end
end

namespace :curb do
  desc "Collect yearly US sales from Wikipedia for the models with the most owner complaints: bin/rails 'curb:sales[200]'"
  task :sales, %i[limit] => :environment do |_, args|
    $stdout.sync = true
    models = ComplaintCount.where(model_year: 2012..2025).group(:make_key, :model_key).order("sum_complaints DESC")
                           .limit((args[:limit] || 200).to_i).sum(:complaints).keys
    models.reject! { |make_key, model_key| ModelSale.exists?(make_key:, model_key:) }
    puts "#{models.size} models to look up"
    found = Importers::WikipediaSales.new.call(models).each do |result|
      puts "  #{result.make_key} #{result.model_key}: #{result.sales.any? ? "#{result.sales.size} years from #{result.page}" : "NOT FOUND"}"
    end
    OwnerReports.clear_cache
    puts "Found #{found.count { |r| r.sales.any? }} of #{found.size}"
  end
end
