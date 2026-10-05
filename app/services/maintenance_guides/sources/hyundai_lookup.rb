module MaintenanceGuides
  module Sources
    # Hyundai's manuals page looks documents up by tag ("2019 HYUNDAI ELANTRA") and answers with that car's
    # owner manual and the year's warranty handbook. It only answers within a browsing session, so this
    # opens the manuals page once for its cookies, as a browser would. The schedule is a chapter of the
    # owner manual.
    class HyundaiLookup < Base
      HOST = "https://owners.hyundaiusa.com".freeze
      PAGE = "#{HOST}/us/en/resources/manuals-warranties".freeze
      LOOKUP = "#{HOST}/bin/common/resourceResult".freeze
      NOT_THE_MANUAL = /warranty|quick reference|getting started|abridged|navigation|multimedia|infotainment/i

      def self.makes = %w[HYUNDAI]

      def find(make:, model:, model_year:)
        name = model.to_s.upcase
        [ name, name.tr(" ", "-") ].uniq.each do |tag_model|
          manual = lookup("#{model_year} HYUNDAI #{tag_model}").find do |doc|
            doc["pageText"].to_s.match?(/owner'?s manual/i) && !doc["pageText"].to_s.match?(NOT_THE_MANUAL) && doc["modelYear"].to_s == model_year.to_s
          end
          next unless manual

          return Guide.new(make: "Hyundai", model:, model_year: model_year.to_i, url: URI.join(HOST, manual["href"]).to_s,
                           title: "Hyundai #{manual["pageText"].to_s.strip}", kind: :owner_manual)
        end
        nil
      end

      private
        def lookup(tags)
          sleep PAUSE unless Rails.env.test?
          response = @http.post(LOOKUP) do |request|
            request.headers["Cookie"] = cookies
            request.headers["X-Requested-With"] = "XMLHttpRequest"
            request.headers["Referer"] = PAGE
            request.headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
            request.body = URI.encode_www_form(resultType: "manualandwarranties", tags:, currenturl: PAGE)
          end
          response.success? ? JSON.parse(response.body) : []
        rescue Faraday::Error, JSON::ParserError
          []
        end

        def cookies
          @cookies ||= begin
            response = @http.get(PAGE)
            Array(response.headers["set-cookie"]).join(", ").scan(/(?:\A|,\s*)([^=;,\s]+=[^;,]*)/).flatten.join("; ")
          rescue Faraday::Error
            ""
          end
        end
    end
  end
end
