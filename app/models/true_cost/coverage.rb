module TrueCost
  # How many more years each kind of warranty lasts from the day of purchase: the factory terms that are
  # left (by time and by miles, whichever runs out first), or a CPO / extended plan if it lasts longer.
  class Coverage
    ADDON_COVERS = {
      "powertrain" => %w[powertrain],
      "comprehensive" => %w[bumper_to_bumper powertrain emissions]
    }.freeze

    # Which coverage pays for a category of each warranty type.
    PAID_BY = {
      "bumper_to_bumper" => %w[bumper_to_bumper],
      "powertrain" => %w[powertrain bumper_to_bumper],
      "emissions" => %w[emissions bumper_to_bumper],
      "corrosion" => %w[corrosion],
      "none" => []
    }.freeze

    LABELS = {
      "bumper_to_bumper" => "Bumper-to-bumper", "powertrain" => "Powertrain",
      "corrosion" => "Corrosion", "emissions" => "Emissions"
    }.freeze

    Line = Data.define(:coverage_type, :label, :years_left, :source, :note)

    attr_reader :lines

    def initialize(inputs, terms)
      @inputs = inputs
      @lines = WarrantyTerm::COVERAGE_TYPES.map { |type| line_for(type, terms.find { |term| term.coverage_type == type }) }
    end

    def years_left(coverage_type) = @lines.find { |line| line.coverage_type == coverage_type }&.years_left.to_f

    # Share of ownership year t (1-based) during which a category's repairs are covered: 1, 0, or a fraction.
    def covered(warranty_type, t)
      left = PAID_BY.fetch(warranty_type, []).map { |type| years_left(type) }.max.to_f
      (left - (t - 1)).clamp(0.0, 1.0)
    end

    private
      def line_for(type, term)
        factory, note = factory_years(term)
        addon = addon_years(type)
        if addon > factory
          Line.new(coverage_type: type, label: LABELS[type], years_left: addon, source: @inputs.addon_warranty, note: nil)
        else
          Line.new(coverage_type: type, label: LABELS[type], years_left: factory, source: term ? "factory" : "none", note:)
        end
      end

      def factory_years(term)
        return [ 0.0, nil ] unless term
        return [ 0.0, "Does not transfer to a second owner" ] unless term.transferable
        by_time = term.years - @inputs.age_now
        by_miles = term.miles ? (term.miles - @inputs.mileage).to_f / @inputs.miles_per_year : Float::INFINITY
        [ [ by_time, by_miles ].min.clamp(0.0, 99.0), nil ]
      end

      def addon_years(type)
        return 0.0 if @inputs.addon_warranty == "none"
        return 0.0 unless ADDON_COVERS.fetch(@inputs.addon_coverage.to_s, []).include?(type)
        by_time = @inputs.addon_years.to_f
        by_miles = @inputs.addon_miles.to_i.positive? ? @inputs.addon_miles.to_f / @inputs.miles_per_year : Float::INFINITY
        [ by_time, by_miles ].min
      end
  end
end
