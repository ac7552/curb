module Nhtsa
  # Official US recalls for a make, model and year. Free, no key. https://www.nhtsa.gov/nhtsa-datasets-and-apis
  class Recalls
    URL = "https://api.nhtsa.gov/"

    def initialize(connection: HttpClient.build(URL)) = @connection = connection

    def for_vehicle(make:, model:, model_year:)
      body = HttpClient.get(@connection, "recalls/recallsByVehicle", { make:, model:, modelYear: model_year })
      categories = DefectCategory.all.to_a
      Array(body["results"]).map do |row|
        {
          campaign: row["NHTSACampaignNumber"],
          component: row["Component"],
          summary: row["Summary"],
          remedy: row["Remedy"],
          reported_on: parse_date(row["ReportReceivedDate"]),
          category: DefectCategory.match(row["Component"], categories)&.slug
        }
      end
    end

    # Keeps a copy of each campaign so a lookup still has recalls if the API is down.
    def self.store(recalls, make_key:, model_key:, model_year:)
      rows = recalls.map do |recall|
        Recall.new(campaign_number: recall[:campaign], country: "US", make_key:, model_key:,
                   year_from: model_year, year_to: model_year, component: recall[:component],
                   summary: recall[:summary], remedy: recall[:remedy], reported_on: recall[:reported_on],
                   defect_category: DefectCategory.find_by(slug: recall[:category]))
      end
      Recall.import(rows, on_duplicate_key_update: {
        conflict_target: [ :campaign_number ],
        columns: %i[component summary remedy reported_on defect_category_id updated_at]
      })
    end

    private
      def parse_date(value)
        return if value.blank?
        Date.strptime(value.to_s[0, 10], value.to_s.include?("/") ? "%d/%m/%Y" : "%Y-%m-%d").iso8601
      rescue Date::Error
        nil
      end
  end
end
