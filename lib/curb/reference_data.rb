module Curb
  # Loads the hand-built reference tables from db/seeds/*.yml. Safe to re-run.
  module ReferenceData
    module_function

    def load!(dir = Rails.root.join("db/seeds"))
      dir = Pathname(dir)

      YAML.load_file(dir.join("defect_categories.yml")).each do |row|
        DefectCategory.find_or_initialize_by(slug: row["slug"]).update!(row)
      end

      YAML.load_file(dir.join("warranty_terms.yml")).each do |country, makes|
        makes.each do |make_key, coverages|
          coverages.each do |coverage_type, (years, miles)|
            WarrantyTerm.find_or_initialize_by(country:, make_key:, coverage_type:, model_year_from: nil, model_year_to: nil)
                        .update!(years:, miles:, transferable: true)
          end
        end
      end

      YAML.load_file(dir.join("service_items.yml")).each do |row|
        ServiceItem.find_or_initialize_by(make_key: row["make_key"], model_key: row["model_key"], name: row["name"])
                   .update!(row.except("make_key", "model_key", "name"))
      end

      YAML.load_file(dir.join("labor_rates.yml")).each do |country, regions|
        regions.each do |region, shops|
          shops.each do |shop_type, hourly_rate|
            LaborRate.find_or_initialize_by(country:, region:, shop_type:).update!(hourly_rate:)
          end
        end
      end

      # Schedules read from makers' guides ahead of time (bin/rails curb:guides:prefill).
      Dir.glob(dir.join("maintenance_guides/**/*.json")).sort.each { |path| MaintenanceGuides::Prefill.load_file(path) }
    end
  end
end
