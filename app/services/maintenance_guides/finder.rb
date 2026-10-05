module MaintenanceGuides
  # Finds a car's maintenance schedule document by asking the source for its make (app/services/
  # maintenance_guides/sources). Makers that block programs (Ford, Lincoln, Kia, Stellantis, BMW, MINI,
  # Volvo, Genesis) have no source and stay on the generic schedule. See docs/plans/maintenance-schedules-from-manuals.md.
  class Finder
    SOURCES = [ Sources::AddressPattern, Sources::GmSearch, Sources::HyundaiLookup, Sources::AddressFile, Sources::NhtsaFiling ].freeze

    def self.supported_makes = SOURCES.flat_map(&:makes).uniq

    def initialize(http: nil)
      @sources = SOURCES.to_h { |source| [ source, source.new(http:) ] }
    end

    def supports?(make) = self.class.supported_makes.include?(VehicleName.make_key(make))

    # A Guide, or nil when the maker isn't supported or has no guide for this car.
    def find(make:, model:, model_year:)
      source = SOURCES.find { |candidate| candidate.makes.include?(VehicleName.make_key(make)) } or return
      @sources[source].find(make:, model:, model_year:)
    end
  end
end
