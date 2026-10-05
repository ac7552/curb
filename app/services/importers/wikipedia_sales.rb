require "net/http"

module Importers
  # Yearly US sales for car models from Wikipedia model pages (text under CC BY-SA 4.0; each figure keeps
  # its page as the source). A page is found with Wikipedia's search API, or from db/seeds/sales_pages.yml
  # when search picks the wrong page. The sales table used is the wikitable whose header starts with a
  # year column and has a US column; when a page has several (a hybrid-only table, say), the biggest wins.
  class WikipediaSales
    API = URI("https://en.wikipedia.org/w/api.php")
    USER_AGENT = "CurbCarCosts/1.0 (used-car cost research)"
    YEARS = 2010..2025

    Result = Data.define(:make_key, :model_key, :page, :sales)

    MAX_RETRIES = 4

    def initialize(overrides: YAML.load_file(Rails.root.join("db/seeds/sales_pages.yml")), pause: 2)
      @overrides = overrides
      @pause = pause
    end

    # Finds and stores sales for each [make_key, model_key]; returns Results (sales empty when not found).
    def call(models)
      models.map do |make_key, model_key|
        result = find(make_key, model_key)
        store(result) if result.sales.any?
        result
      end
    end

    def find(make_key, model_key)
      overrides = Array(@overrides.dig(make_key, model_key))
      titles = overrides.presence || search("#{make_key.titleize} #{model_key.titleize}").select { |title| names_model?(title, make_key, model_key) }
      titles.each do |title|
        sales = us_sales(page_html(title))
        return Result.new(make_key:, model_key:, page: title, sales:) if sales.size >= 3
      end
      Result.new(make_key:, model_key:, page: nil, sales: {})
    end

    # Year => units from the page's biggest US sales table, within YEARS. The US column can be in the
    # first header row ("Year | U.S. | Canada", "Calendar year | Explorer (US)") or, under a "Sales"
    # heading, in the second ("Year | Sales" then "U.S. | Japan | ...").
    def us_sales(html)
      return {} if html.blank?
      Nokogiri::HTML(html).css("table.wikitable").filter_map do |table|
        rows = table.css("tr").map { |tr| tr.css("th, td").map { |cell| cell.text.gsub(/\[[^\]]*\]/, "").strip } }
        next unless rows.first.to_a.first.to_s.match?(/year/i)
        column, data = if (us = us_column(rows[0])) then [ us, rows.drop(1) ]
        elsif (us = us_column(rows[1])) then [ us + 1, rows.drop(2) ]
        end
        next unless column
        data.filter_map do |cells|
          year = cells.first.to_s[/\A(19|20)\d\d/].to_i
          units = cells[column].to_s.gsub(/[,\s]/, "")[/\A\d{3,7}\z/].to_i
          [ year, units ] if YEARS.cover?(year) && units.positive?
        end.to_h.presence
      end.max_by { |sales| sales.values.sum } || {}
    end

    def us_column(cells)
      Array(cells).index { |cell| cell.match?(/(\A|\(|\s)(U\.\s?S\.?(A\.?)?|USA?|United States)(\z|\)|\s)/) && !cell.match?(/police|fleet/i) }
    end

    # A search result is only used when its title is the model ("Jeep Grand Cherokee" isn't a Cherokee page,
    # "Ford Mustang Mach-E" isn't a Mustang one). A generation in brackets is fine: "Dodge Dart (PF)".
    def names_model?(title, make_key, model_key)
      normalize = ->(text) { text.downcase.tr("-", " ").squeeze(" ").strip }
      base = normalize.(title.sub(/\s*\(.*\)\z/, ""))
      [ "#{make_key} #{model_key}", model_key ].map(&normalize).include?(base)
    end

    private
      def store(result)
        now = Time.current
        rows = result.sales.map do |year, units|
          { make_key: result.make_key, model_key: result.model_key, year:, units:, source: "wikipedia",
            source_url: "https://en.wikipedia.org/wiki/#{ERB::Util.url_encode(result.page.tr(" ", "_"))}", created_at: now, updated_at: now }
        end
        ModelSale.upsert_all(rows, unique_by: %i[make_key model_key year])
      end

      def search(query)
        get({ action: "query", list: "search", srsearch: query, srlimit: 3 }).dig("query", "search").to_a.map { |hit| hit["title"] }
      end

      def page_html(title)
        get({ action: "parse", page: title, prop: "text", redirects: 1 }).dig("parse", "text")
      end

      # Waits between requests and, when Wikipedia says to slow down (429), waits as long as it asks.
      def get(params, attempt: 1)
        sleep @pause
        uri = API.dup
        uri.query = URI.encode_www_form(params.merge(format: "json", formatversion: 2, maxlag: 5))
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
          http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT))
        end
        if response.code == "429" && attempt <= MAX_RETRIES
          sleep [ response["retry-after"].to_i, 5 ].max * attempt
          return get(params, attempt: attempt + 1)
        end
        response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : {}
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, JSON::ParserError
        {}
      end
  end
end
