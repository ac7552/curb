module Wikimedia
  # A free photo of a car from Wikimedia Commons, with the credit its license asks for. Commons files
  # are usually titled "2019 Toyota Tacoma SR5, front right", so the search favours the model year at
  # the start and a front view, and skips interiors, engines and close-ups.
  class CarPhoto
    URL = "https://commons.wikimedia.org/"
    WIDTH = 1000
    FREE_LICENSE = /\A(CC BY(-SA)? \d|CC0|Public domain)/i
    CLOSE_UP = /\b(rear|back|interior|engine|dashboard|dash|cockpit|steering|gauges?|badge|logo|emblem|wheels?|rims?|seats?|trunk|boot|tail ?lights?|headlights?|grille|key|crash|wreck|damaged|police)\b/i

    def initialize(connection: HttpClient.build(URL, headers: { "User-Agent" => "Curb/1.0 (used-car cost checker)" }))
      @connection = connection
    end

    # { url:, page:, title:, artist:, license:, license_url: } or nil. Tries the exact model year, then
    # any year of the model.
    def find(make:, model:, model_year:)
      pick(search("#{model_year} #{make} #{model}"), make:, model:, model_year:) ||
        pick(search("#{make} #{model}"), make:, model:, model_year:)
    end

    private
      def search(query)
        HttpClient.get(@connection, "w/api.php", {
          action: "query", format: "json", generator: "search", gsrnamespace: 6, gsrlimit: 15, gsrsearch: query,
          prop: "imageinfo", iiprop: "url|extmetadata|mime|size", iiurlwidth: WIDTH,
          iiextmetadatafilter: "LicenseShortName|LicenseUrl|Artist"
        }).dig("query", "pages")&.values.to_a
      end

      def pick(pages, make:, model:, model_year:)
        words = [ make, model ].join(" ").downcase.scan(/[[:alnum:]]+/)
        scored = pages.filter_map do |page|
          info = page.dig("imageinfo", 0) or next
          meta = info["extmetadata"] || {}
          title = page["title"].to_s.delete_prefix("File:").sub(/\.\w+\z/, "")
          license = meta.dig("LicenseShortName", "value").to_s
          next unless info["mime"].in?(%w[image/jpeg image/png]) && info["width"].to_i >= WIDTH
          next unless license.match?(FREE_LICENSE) && words.all? { |word| title.downcase.include?(word) }
          next if title.match?(CLOSE_UP)

          score = 0
          score += 4 if title.start_with?("#{model_year} ")
          score += 1 if title.include?(model_year.to_s)
          score -= 3 if title.match?(/\A(19|20)\d\d\b/) && !title.start_with?(model_year.to_s)
          score += 2 if title.match?(/\bfront\b/i)
          [ score, -page["index"].to_i, page, info, meta, title, license ]
        end
        _, _, page, info, meta, title, license = scored.max_by { |row| row.first(2) }
        return unless page

        { url: info["thumburl"] || info["url"], page: info["descriptionurl"], title:,
          artist: ActionView::Base.full_sanitizer.sanitize(meta.dig("Artist", "value").to_s).squish.truncate(60).presence,
          license:, license_url: meta.dig("LicenseUrl", "value") }
      end
  end
end
