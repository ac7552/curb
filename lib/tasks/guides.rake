# Reading makers' maintenance guides. Plain rules read most guides in seconds; Claude is the fallback for
# the ones they can't, when there's an API key (ANTHROPIC_API_KEY or credentials.anthropic_api_key).
namespace :curb do
  namespace :guides do
    desc "Read one maintenance guide: bin/rails 'curb:guides:extract[Toyota,Tacoma,2019]'"
    task :extract, %i[make model year] => :environment do |_, args|
      $stdout.sync = true
      abort "Usage: bin/rails 'curb:guides:extract[Toyota,Tacoma,2019]'" unless args[:make] && args[:model] && args[:year]

      guide = MaintenanceGuides::Finder.new.find(make: args[:make], model: args[:model], model_year: args[:year])
      abort "No maintenance guide found for the #{args[:year]} #{args[:make]} #{args[:model]}." unless guide
      puts "Guide: #{guide.title}\n       #{guide.url}"
      puts(Claude.available? ? "Reading with rules, then #{MaintenanceGuides::ClaudeExtractor::MODEL} if they can't…" : "Reading with rules (no Claude API key to fall back on)…")

      read = MaintenanceGuides::Reader.new.read(guide)
      result = read.result
      out = MaintenanceGuides::Reader::PDF_DIR.join("#{MaintenanceGuides::Reader.slug(guide)}.json")
      File.write(out, JSON.pretty_generate(guide: guide.to_h, status: result.status, rows: result.rows,
                                          problems: result.problems, skipped: result.skipped, extraction: read.extraction))

      puts "Schedule pages: #{read.pages.join(", ")}"
      puts "Read by #{read.extraction["model"]} (#{read.extraction["layout"]}) in #{read.extraction["seconds"]}s\n\n"
      puts format("%-26s %12s %8s  %-8s %s", "Item", "Every (mi)", "(mo)", "Page", "Limited to")
      result.rows.each do |row|
        puts format("%-26s %12s %8s  %-8s %s", row[:name], row[:interval_miles]&.to_fs(:delimited) || "–",
                    row[:interval_months] || "–", "p. #{row[:source_page]}", row[:applies_to])
      end
      puts "\nSkipped #{result.skipped.size} items (inspections, special conditions, or not priced yet)."
      puts(result.problems.any? ? "\nNEEDS REVIEW:\n#{result.problems.map { "  - #{_1}" }.join("\n")}" : "\nLooks right. Check it against the PDF before using it.")
      puts "Full answer saved to #{out.relative_path_from(Rails.root)}"
    rescue MaintenanceGuides::ClaudeExtractor::Error, MaintenanceGuides::Reader::Error => e
      abort e.message
    end

    desc "Read guides for every supported make's best sellers back to 2016 (MAKES=all|Toyota,Nissan TOP=12 FROM=2016 TO=#{Date.current.year + 1} FORCE=1)"
    task prefill: :environment do
      $stdout.sync = true
      warn "No Claude API key, so guides the rules can't read are logged as failures." unless Claude.available?

      requested = ENV.fetch("MAKES", "all")
      makes = requested == "all" ? MaintenanceGuides::Finder.supported_makes.map { |key| VehicleName.display_make(key) } : requested.split(",").map(&:strip)
      years = Integer(ENV.fetch("FROM", 2016))..Integer(ENV.fetch("TO", Date.current.year + 1))
      top = Integer(ENV.fetch("TOP", 12))
      finder = MaintenanceGuides::Finder.new
      supported = makes.select { |make| finder.supports?(make) }
      (makes - supported).each { |make| warn "Skipping #{make}: no automated source for its guides (see docs/plans/maintenance-schedules-from-manuals.md)." }

      cars = MaintenanceGuides::Prefill.popular_cars(makes: supported, top:, years:)
      puts "#{cars.size} cars: #{supported.join(", ")} best sellers (top #{top}), #{years.first}–#{years.last}. Stop with Ctrl+C and run again to carry on.\n\n"
      reader = MaintenanceGuides::Reader.new
      counts = MaintenanceGuides::Prefill.new(finder:, reader:).run(cars, force: ENV["FORCE"].present?)

      puts "\nDone: #{counts[:ok]} ok, #{counts[:needs_review]} need review, #{counts[:not_found]} no guide found, " \
           "#{counts[:failed]} failed, #{counts[:already_done]} already done."
      puts "Saved to db/seeds/maintenance_guides/ (commit these). See failures with: bin/rails curb:guides:failures" if (counts[:not_found] + counts[:failed]).positive?
    rescue MaintenanceGuides::ClaudeExtractor::Unavailable => e
      abort "\nStopped: #{e.message} Run again to carry on from here."
    rescue Interrupt
      abort "\nStopped. Run again to carry on from here."
    end

    desc "Use a guide saved from a browser, for makers whose sites refuse downloads: bin/rails 'curb:guides:import[address,file]'"
    task :import, %i[url file] => :environment do |_, args|
      abort "Usage: bin/rails 'curb:guides:import[https://…/maintenance.pdf,~/Downloads/maintenance.pdf]'" unless args[:url] && args[:file]
      file = Pathname(File.expand_path(args[:file]))
      abort "#{file} isn't a PDF" unless file.exist? && file.binread(5) == "%PDF-"
      target = MaintenanceGuides::Reader.pdf_path(MaintenanceGuides::Guide.new(make: "", model: "", model_year: 0, url: args[:url], title: ""))
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(file, target)
      puts "Saved as #{target.relative_path_from(Rails.root)}; guides at #{args[:url]} are now read from it."
    end

    desc "List cars whose guide couldn't be read, to retry or look at by hand"
    task failures: :environment do
      failures = MaintenanceGuides::Prefill.failures
      puts(failures.empty? ? "No failures." : failures.map { |f| "#{f["model_year"]} #{f["make"]} #{f["model"]}: #{f["error"]}" })
    end
  end
end
