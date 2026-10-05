require "csv"

module Importers
  # Loads NHTSA's manufacturer communications (MFR_COMMS_RECEIVED_*.csv: ID, make, model, model years,
  # summary). Each communication is stored once per make, model and year it covers, with a short title
  # and a category guessed from its summary.
  #
  # https://www.nhtsa.gov/nhtsa-datasets-and-apis#manufacturer-communications
  class NhtsaBulletins
    TITLE_LENGTH = 160

    def initialize(paths, first_model_year: 2000)
      @paths = Array(paths)
      @first_model_year = first_model_year
      @categories = DefectCategory.all.to_a
    end

    # Replaces all bulletins; returns the number of rows written.
    def call
      ServiceBulletin.delete_all
      written = 0
      @paths.each do |path|
        batch = []
        CSV.foreach(path, headers: true, encoding: "bom|utf-8", liberal_parsing: true) do |row|
          batch.concat(rows_for(row))
          next if batch.size < 20_000
          written += insert(batch)
          batch = []
        end
        written += insert(batch)
      end
      ModelProfile.clear_cache
      written
    end

    private
      def rows_for(row)
        summary = row["Concise Summary"].to_s.squish.delete_prefix('"').delete_suffix('"')
        return [] if summary.empty? || row["TSB/Document ID"].blank?
        title = summary.truncate(TITLE_LENGTH, separator: " ")
        # The title names the problem; later sentences often mention unrelated parts.
        slug = DefectCategory.match(title, @categories)&.slug
        make_key = VehicleName.make_key(row["Make"])
        model_key = VehicleName.model_key(row["Model"])
        years = row["Model Year"].to_s.split(",").map(&:to_i).select { |year| year >= @first_model_year && year <= Date.current.year + 1 }
        themes = BulletinTheme.match(title)
        # A bulletin that extends a warranty is a free repair the owner can claim, not an instruction
        # to a technician. See BulletinProgram.
        program_kind = BulletinProgram.match(title)
        years.uniq.map do |model_year|
          { document_id: row["TSB/Document ID"].strip, make_key:, model_key:, model_year:, title:,
            category_slug: slug, themes:, program_kind: }
        end
      end

      def insert(rows)
        return 0 if rows.empty?
        now = Time.current
        ServiceBulletin.insert_all(rows.map { |row| row.merge(created_at: now, updated_at: now) },
                                   unique_by: :index_service_bulletins_on_car_and_document).length
      end
  end
end
