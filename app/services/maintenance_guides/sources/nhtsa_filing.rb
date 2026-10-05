module MaintenanceGuides
  module Sources
    # Makers that file their schedules with NHTSA. VW and Audi file a maintenance schedule per model year
    # ("2018 Audi Maintenance Schedule - All Models"); Tesla files its owner's manual, whose "Maintenance
    # Service Intervals" section is the schedule. Those filings are already in service_bulletins; the PDF
    # is at static.nhtsa.gov/odi/tsbs/<year filed>/MC-<id>-<part>.pdf. The year filed is usually around the
    # model year (later for Tesla, which files new manuals as they change) and the part is usually 9999
    # or 0001, so a few addresses are tried, newest filing first.
    class NhtsaFiling < Base
      SCHEDULES = [ "%maintenance schedule%", "%scheduled maintenance%", "%maintenance intervals%" ].freeze
      TITLES = { "VOLKSWAGEN" => SCHEDULES, "AUDI" => SCHEDULES, "TESLA" => [ "%owner%manual%" ] }.freeze
      PARTS = %w[9999 0001].freeze

      def self.makes = TITLES.keys

      def find(make:, model:, model_year:)
        year = model_year.to_i
        make_key = VehicleName.make_key(make)
        filings = ServiceBulletin.where(make_key:, model_key: VehicleName.model_key(model), model_year: year)
                                 .where("title ILIKE ANY (array[?])", TITLES.fetch(make_key, [])).where("title NOT ILIKE ?", "%incorrect%")
                                 .distinct.order(document_id: :desc).pluck(:document_id, :title).first(3)
        filings.each do |document_id, title|
          filed_years = [ year - 1, year, year - 2, year + 1 ] | (year..Date.current.year).to_a.reverse
          filed_years.product(PARTS).each do |filed, part|
            url = "https://static.nhtsa.gov/odi/tsbs/#{filed}/MC-#{document_id}-#{part}.pdf"
            next unless pdf?(url)
            return Guide.new(make: VehicleName.display_make(make), model:, model_year: year, url:,
                             title: "#{title.to_s.truncate(90)} (NHTSA #{document_id})", kind: :nhtsa_filing)
          end
        end
        nil
      end
    end
  end
end
