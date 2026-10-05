module MaintenanceGuides
  module Sources
    # Makers whose booklets sit at addresses that can't be guessed (Subaru, Mitsubishi, Jeep's handbooks in
    # Fiat's eLUM library). The addresses are listed by hand in db/seeds/guide_addresses.yml: a row covers a
    # year or years, and either every model or the models it names; a row naming the car wins. A year with
    # no address yet simply has no guide, and the batch logs it.
    class AddressFile < Base
      cattr_accessor :path, default: Rails.root.join("db/seeds/guide_addresses.yml")

      def self.makes = entries.keys

      def self.entries
        YAML.load_file(path).transform_keys { |make| VehicleName.make_key(make) }
      end

      def find(make:, model:, model_year:)
        model_key = VehicleName.model_key(model)
        rows = self.class.entries.fetch(VehicleName.make_key(make), []).select do |row|
          year_covered?(row["years"], model_year.to_i) && (row["models"].blank? || Array(row["models"]).any? { VehicleName.model_key(_1) == model_key })
        end
        entry = rows.find { _1["models"].present? } || rows.first
        # A book imported from a browser (bin/rails curb:guides:import) counts, for sites that refuse downloads.
        imported = entry && Reader.pdf_path(Guide.new(make:, model:, model_year:, url: entry["url"], title: "")).exist?
        return unless entry && (imported || pdf?(entry["url"]))

        Guide.new(make: VehicleName.display_make(make), model:, model_year: model_year.to_i, url: entry["url"],
                  title: entry["title"], kind: (entry["kind"] || "all_models_booklet").to_sym)
      end

      private
        # years: 2021, [2020, 2021] or "2020-2021"
        def year_covered?(years, year)
          Array(years).map(&:to_i).include?(year) || years.to_s.split("-").map(&:to_i).then { |a, b| b && (a..b).cover?(year) }
        end
    end
  end
end
