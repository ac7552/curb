module MaintenanceGuides
  module Sources
    # What every source shares: one polite HTTP client, and a check that an address really is a PDF
    # (fetching only its first kilobyte). Sources return a Guide, or nil when the maker has none for that car.
    class Base
      USER_AGENT = "Mozilla/5.0 (compatible; Curb/1.0; used-car cost checker)".freeze
      PAUSE = 0.5 # seconds between requests to the same maker

      def initialize(http: nil)
        @http = http || Faraday.new(headers: { "User-Agent" => USER_AGENT }) do |f|
          f.options.timeout = 25
          f.options.open_timeout = 10
        end
      end

      def find(make:, model:, model_year:) = raise NotImplementedError

      private
        def pdf?(url, redirects: 2)
          sleep PAUSE unless Rails.env.test?
          response = @http.get(url) { |request| request.headers["Range"] = "bytes=0-1023" }
          if response.status.in?([ 301, 302, 303, 307, 308 ]) && redirects.positive? && response.headers["location"]
            return pdf?(URI.join(url, response.headers["location"]).to_s, redirects: redirects - 1)
          end
          # Some servers (NHTSA's newer filings) send PDFs as plain octet-stream; the file's first bytes say.
          response.status.in?([ 200, 206 ]) && (response.headers["content-type"].to_s.include?("pdf") || response.body.to_s.start_with?("%PDF"))
        rescue Faraday::Error, URI::Error
          false
        end
    end
  end
end
