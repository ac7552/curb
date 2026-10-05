module MaintenanceGuides
  module Sources
    # Chevrolet, GMC, Buick and Cadillac: GM's manuals page searches its own document index, which answers
    # "+2019 +CHEVROLET +EQUINOX" with that car's owner manual (and warranty and quick-start guides). The
    # schedule is a chapter of the owner manual. This sends the same search the page does.
    class GmSearch < Base
      MAKES = %w[CHEVROLET GMC BUICK CADILLAC].freeze
      URL = "https://contentdelivery.ext.gm.com/bypass/gma-search-api/searchapi/solr/gma-public/select".freeze
      FIELDS = "defType=edismax&fl=imdocid,imcontent_text_id,path,title_ordered,category_key,file_type&fq=channel:*MANUALS*" \
               "&fq=source:aem&fq=file_type:application/pdf&fq=locale:en_US&".freeze
      WEIGHTS = "&qf=title_en^200.0 title_es^200 title_ar^200 title_pt^200 title_ru^200 title_th^200 title_fr^200 title_ko^200 " \
                "category_translated^150.0 category_translated_path^120.0 category_key_path^90.0 mmy^80.0 category_key^75" \
                "&stopwords=true&useParams=default".freeze
      # Owner manuals for other bodies or fleets that share the model's name.
      OTHER_VERSION = /\b(LTD|Limited|HD|2500|3500|4500|Fleet|Supplement)\b/i

      def self.makes = MAKES

      def find(make:, model:, model_year:)
        query = "#{FIELDS}q=+#{model_year} +#{VehicleName.make_key(make)} +#{model.to_s.upcase}&rows=20#{WEIGHTS}"
        response = @http.get("#{URL}?#{ERB::Util.url_encode(query)}")
        return unless response.success?

        docs = JSON.parse(response.body).dig("response", "docs").to_a
        manual = docs.map { |doc| [ Array(doc["title_ordered"]).first.to_s, doc["path"] ] }.find do |title, _|
          title.match?(/\A#{model_year}\b.*\b#{Regexp.escape(model.to_s)}\b.*Owner(?:'s)? Manual\z/i) &&
            (title.match?(OTHER_VERSION) == model.to_s.match?(OTHER_VERSION))
        end
        return unless manual

        Guide.new(make: VehicleName.display_make(make), model:, model_year: model_year.to_i, url: manual.last,
                  title: manual.first, kind: :owner_manual)
      rescue Faraday::Error, JSON::ParserError
        nil
      end
    end
  end
end
