module Mot
  # DVSA MOT History API: one UK car's full test history by registration, including advisories.
  # Needs registration (https://documentation.history.mot.api.gov.uk/mot-history-api/register) and
  # four settings: MOT_CLIENT_ID, MOT_CLIENT_SECRET, MOT_API_KEY, MOT_TENANT_ID (env or credentials).
  class HistoryClient
    API_URL = "https://history.mot.api.gov.uk/"
    SCOPE = "https://tapi.dvsa.gov.uk/.default"
    TOKEN_CACHE_KEY = "mot/access_token"

    def self.configured? = settings.values.all?(&:present?)

    def self.settings
      %i[client_id client_secret api_key tenant_id].index_with do |name|
        ENV["MOT_#{name.upcase}"].presence || Rails.application.credentials.dig(:mot, name)
      end
    end

    def initialize(connection: HttpClient.build(API_URL), token_connection: HttpClient.build("https://login.microsoftonline.com/"))
      @connection = connection
      @token_connection = token_connection
    end

    def vehicle(registration)
      body = HttpClient.get(@connection, "v1/trade/vehicles/registration/#{registration}", headers: auth_headers)
      tests = Array(body["motTests"]).map { |test| parse_test(test) }.sort_by { |test| test[:completed_on].to_s }.reverse

      VehicleMatch.new(
        source: "DVSA MOT",
        make: body["make"].to_s.titleize,
        model: body["model"].to_s,
        engine: body["engineSize"].to_i.positive? ? format("%.1fL", body["engineSize"].to_i / 1000.0) : nil,
        fuel_type: body["fuelType"],
        first_used_on: (Date.parse(body["firstUsedDate"].to_s) rescue nil),
        history: { source: "MOT", tests: tests.first(5) }
      )
    rescue HttpClient::Error => e
      raise unless e.message.include?("404")
      nil
    end

    private
      def auth_headers
        { "Authorization" => "Bearer #{access_token}", "X-API-Key" => self.class.settings[:api_key] }
      end

      # Tokens last 60 minutes; keep one for 55.
      def access_token
        Rails.cache.fetch(TOKEN_CACHE_KEY, expires_in: 55.minutes) do
          settings = self.class.settings
          response = @token_connection.post("#{settings[:tenant_id]}/oauth2/v2.0/token") do |request|
            request.headers["Content-Type"] = "application/x-www-form-urlencoded"
            request.body = URI.encode_www_form(grant_type: "client_credentials", client_id: settings[:client_id],
                                               client_secret: settings[:client_secret], scope: SCOPE)
          end
          response.body.fetch("access_token")
        end
      rescue Faraday::Error => e
        raise HttpClient::Error, "MOT token: #{e.message}"
      end

      def parse_test(test)
        miles = test["odometerValue"].to_i
        miles = (miles / Market::KM_PER_MILE).round if test["odometerUnit"].to_s.downcase.start_with?("k")
        {
          completed_on: (Date.parse(test["completedDate"].to_s).iso8601 rescue nil),
          result: test["testResult"],
          mileage: miles.positive? ? miles : nil,
          defects: Array(test["defects"]).map do |defect|
            { text: defect["text"], type: defect["type"], dangerous: defect["dangerous"] == true }
          end
        }
      end
  end
end
