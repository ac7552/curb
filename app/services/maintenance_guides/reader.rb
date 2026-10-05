module MaintenanceGuides
  # Reads one guide end to end: download (kept in tmp/guides so re-runs don't fetch again), then read the
  # schedule with plain rules (RuleExtractor), and check the result. Only when the rules can't give a
  # clean reading is Claude asked (ClaudeExtractor), when there's an API key. Runs on a developer's
  # machine; see bin/rails curb:guides:extract (one car) and curb:guides:prefill (many).
  class Reader
    class Error < StandardError; end

    PDF_DIR = Rails.root.join("tmp/guides")
    MAX_PDF_BYTES = 100.megabytes # Hyundai's owner's manuals run to 60 MB

    Read = Data.define(:guide, :result, :extraction, :pages)

    # extractor: the model to fall back on, or nil to read with rules only.
    def initialize(extractor: (ClaudeExtractor.new if Claude.available?), rules: RuleExtractor.new, http: nil)
      @extractor = extractor
      @rules = rules
      @http = http || Faraday.new(headers: { "User-Agent" => "Curb/1.0 (used-car cost checker)" }) { |f| f.options.timeout = 60 }
    end

    def read(guide)
      pdf = download(guide)
      by_rules = read_with_rules(guide, pdf)
      return by_rules if by_rules&.result&.status == "ok" || (@extractor.nil? && by_rules)
      raise Error, "The rules couldn't find a schedule in this guide, and there's no Claude API key to try with" unless @extractor

      begin
        by_model = read_with_model(guide, pdf)
      rescue ClaudeExtractor::Unavailable
        raise # every guide would fail the same way
      rescue ClaudeExtractor::Error, Error
        raise unless by_rules # nothing else to go on
        return by_rules
      end
      by_rules && by_model.result.status != "ok" ? by_rules : by_model
    rescue StandardError => e
      raise unless pdf_error?(e)
      raise Error, "Couldn't read the PDF: #{e.message}"
    end

    def self.slug(guide) = [ guide.model_year, guide.make, guide.model ].join("-").parameterize

    # Downloads are kept by address, so a booklet covering every model is fetched once, not once a model.
    def self.pdf_path(guide) = PDF_DIR.join("#{Digest::SHA256.hexdigest(guide.url)[0, 16]}.pdf")

    private
      # pdf-reader is only loaded once a guide is opened, so its errors can't be named before then.
      def pdf_error?(error)
        defined?(PDF::Reader::MalformedPDFError) && error.is_a?(PDF::Reader::MalformedPDFError) ||
          defined?(PDF::Reader::UnsupportedFeatureError) && error.is_a?(PDF::Reader::UnsupportedFeatureError)
      end

      def read_with_rules(guide, pdf)
        extraction = @rules.extract(pdf, guide:) or return
        Read.new(guide:, result: Validator.new(guide).check(extraction), extraction:, pages: extraction["pages"])
      end

      def read_with_model(guide, pdf)
        pages = schedule_pages(pdf)

        extraction = @extractor.extract(pages, guide:)
        Read.new(guide:, result: Validator.new(guide).check(extraction), extraction:, pages: pages.map(&:number))
      end

      def schedule_pages(pdf)
        text = PdfText.new(pdf)
        text.schedule_pages.presence or raise Error, "No schedule pages among the guide's #{text.page_count} pages"
      end

      def download(guide)
        FileUtils.mkdir_p(PDF_DIR)
        path = self.class.pdf_path(guide)
        return path if path.exist?

        response = get(guide.url)
        raise Error, "Download failed (HTTP #{response.status})" unless response.success?
        raise Error, "Guide is too big (#{response.body.bytesize / 1.megabyte} MB)" if response.body.bytesize > MAX_PDF_BYTES
        File.binwrite(path, response.body)
        path
      rescue Faraday::Error => e
        raise Error, "Download failed: #{e.message}"
      end

      def get(url, redirects: 2)
        response = @http.get(url)
        return response unless response.status.in?([ 301, 302, 303, 307, 308 ]) && redirects.positive? && response.headers["location"]
        get(URI.join(url, response.headers["location"]).to_s, redirects: redirects - 1)
      end
  end
end
