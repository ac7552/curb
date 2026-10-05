module MaintenanceGuides
  module Sources
    # Makers whose guides sit at addresses built from the year and model. Each maker gives a list of
    # candidate addresses, most likely first, because spellings vary ("Civic Sedan", "rogue_sport",
    # "mazda3-4door"); the first one that is really a PDF wins.
    class AddressPattern < Base
      # Lexus guides are named for the variant ("RX350", "ES250ES350"); NHTSA lists the family ("RX").
      LEXUS_VARIANTS = {
        "RX" => %w[RX350 RX350L RX450h RX], "ES" => %w[ES350 ES250ES350 ES300h ES], "NX" => %w[NX300 NX350 NX300h NX350h NX],
        "IS" => %w[IS300 IS350 IS200t IS], "GX" => %w[GX460 GX550 GX], "LX" => %w[LX570 LX600 LX], "UX" => %w[UX200 UX250h UX],
        "RC" => %w[RC300 RC350 RC], "LS" => %w[LS500 LS460 LS], "LC" => %w[LC500 LC500LC500C LC], "GS" => %w[GS350 GS300 GS]
      }.freeze
      HONDA_BODIES = { "Sedan" => "4D", "Coupe" => "2D", "Hatchback" => "5D" }.freeze

      MAKERS = {
        "TOYOTA" => lambda do |model, year|
          code = format("%02d%s", year % 100, model.gsub(/[^A-Za-z0-9]/, ""))
          [ [ "https://assets.sia.toyota.com/publications/en/omms-s/T-MMS-#{code}/pdf/T-MMS-#{code}.pdf",
              "Toyota #{year} #{model} Warranty & Maintenance Guide", :maintenance_guide ] ]
        end,
        "LEXUS" => lambda do |model, year|
          family = model.gsub(/[^A-Za-z]/, "").upcase[0, 2]
          variants = (LEXUS_VARIANTS[family] || []) | [ model.gsub(/[^A-Za-z0-9]/, "") ]
          variants.map do |variant|
            code = format("%02d%s", year % 100, variant)
            [ "https://assets.sia.toyota.com/publications/en/omms-s/L-MMS-#{code}/pdf/L-MMS-#{code}.pdf",
              "Lexus #{year} #{model} Warranty and Services Guide", :maintenance_guide ]
          end
        end,
        "NISSAN" => lambda do |model, year|
          dashed = model.downcase.gsub(/[^a-z0-9]+/, "-")
          compact = model.gsub(/[^A-Za-z0-9]/, "")
          title = "Nissan #{year} #{model} Owner's Manual and Maintenance Information"
          base = "https://www.nissanusa.com/content/dam/Nissan/us/manuals-and-guides"
          [ "#{base}/#{dashed}/#{year}/#{year}-nissan-#{dashed}-owner-manual.pdf",
            "#{base}/#{dashed.tr("-", "_")}/#{year}/#{year}-nissan-#{dashed}-owner-manual.pdf",
            "#{base}/#{dashed.tr("-", "_")}/#{year}/#{year}-Nissan-#{compact}-owner-manual.pdf",
            "https://owners.nissanusa.com/content/techpub/ManualsAndGuides/#{compact}/#{year}/#{year}-#{compact}-owner-manual.pdf" ]
            .uniq.map { |url| [ url, title, :owner_manual ] }
        end,
        "INFINITI" => lambda do |model, year|
          slug = model.downcase.gsub(/[^a-z0-9]/, "")
          title = "INFINITI #{year} #{model} Owner's Manual and Maintenance Information"
          [ slug, "#{slug}-sedan", "#{slug}_sedan", "#{slug}-coupe" ].map do |folder|
            [ "https://www.infinitiusa.com/content/dam/Infiniti/US/manuals_guides/#{folder}/#{year}/#{year}-infiniti-#{folder}-owner-manual.pdf", title, :owner_manual ]
          end
        end,
        "HONDA" => lambda do |model, year|
          base = model.sub(/\s+(Sedan|Coupe|Hatchback)\z/i, "")
          folders = [ [ base, nil ] ] + HONDA_BODIES.map { |body, code| [ "#{base} #{body}", code ] }
          folders.flat_map do |folder, code|
            names = [ "#{year}_#{base}_Maintenance_Minder_System", "#{year}_#{base}_Maintenance_Minder" ]
            names += [ "#{year}_#{base}_#{code}_Maintenance_Minder", "#{year}_#{base}_#{code}_Maintenance_Minder_System",
                       "#{year}_#{base.upcase}_#{code}_Maintenance_Minder" ] if code
            names.product([ ".pdf", ".PDF" ]).map do |name, ext|
              path = ERB::Util.url_encode("/static/pdfs/#{year}/#{folder}/#{name}#{ext}")
              [ "https://owners.honda.com/utility/download?path=#{path}", "Honda #{year} #{model} Maintenance Minder", :maintenance_guide ]
            end
          end
        end,
        "ACURA" => lambda do |model, year|
          base = model.upcase.gsub(/\s+/, "")
          %w[_Maintenance_Minder_System _Maintenance_Minder].map do |suffix|
            path = ERB::Util.url_encode("/static/pdfs/#{year}/#{base}/#{year}_#{base}#{suffix}.pdf")
            [ "https://owners.acura.com/utility/download?path=#{path}", "Acura #{year} #{model} Maintenance Minder", :maintenance_guide ]
          end
        end,
        # Genesis's US owner's manuals; the schedule is a grid printed sideways, which Rules::Grid turns.
        "GENESIS" => lambda do |model, year|
          slug = model.to_s.downcase.gsub(/[^a-z0-9]/, "")
          name = model.to_s.upcase.gsub(/[^A-Z0-9]/, "")
          base = "https://owners.genesis.com/genesis/us/mygenesis/manuals/glovebox-manual/#{year}/#{slug}"
          [ "#{year}-#{name}-Owners-Manual.pdf", "#{year}-Genesis-#{name}-Owners-Manual.pdf", "#{year.to_s[2, 2]}MY%20#{name}%20OM.pdf" ].map do |file|
            [ "#{base}/#{file}", "Genesis #{year} #{model} Owner's Manual", :owner_manual ]
          end
        end,
        "MAZDA" => lambda do |model, year|
          slug = model.downcase.gsub(/\s+/, "-")
          slugs = [ slug, ("#{slug}-miata" if slug == "mx-5"), slug.delete_prefix("mazda-") ].compact.uniq
          folders = slugs.flat_map { |s| [ s, "#{s}-4door", "#{s}-5door", "#{s}-sedan", "#{s}-hatchback" ] }.uniq
          folders.flat_map do |folder|
            name = folder.sub(/-(4door|5door|sedan)\z/, "")
            [ "#{year}-#{name}-scheduled-maintenance.pdf", "#{year}_#{name}_schedule_maintenance.pdf",
              "#{year}-mazda-#{name}-scheduled-maintenance.pdf", "#{year}-#{folder}-scheduled-maintenance.pdf" ].uniq.map do |file|
              [ "https://www.mazdausa.com/siteassets/pdf/owners-optimized/#{year}/#{folder}/#{file}",
                "Mazda #{year} #{model} Scheduled Maintenance", :maintenance_guide ]
            end
          end
        end
      }.freeze

      def self.makes = MAKERS.keys

      def find(make:, model:, model_year:)
        builder = MAKERS[VehicleName.make_key(make)] or return
        builder.call(model.to_s, model_year.to_i).each do |url, title, kind|
          return Guide.new(make: VehicleName.display_make(make), model:, model_year: model_year.to_i, url:, title:, kind:) if pdf?(url)
        end
        nil
      end
    end
  end
end
