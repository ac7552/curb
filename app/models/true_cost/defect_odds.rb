module TrueCost
  # Chance that an inspection on this model finds a defect in a category, for a given age and mileage band.
  #
  #   P = (failures + k * p_bar * r) / (tests + k)
  #
  # p_bar is the category's rate across every model in the same age and mileage band, and r is how this
  # model compares with the average car at ages near this car's (its failures over the failures an
  # average car would have had in the same tests). So a thin cell is pulled toward "the average car,
  # adjusted for this model", and an age with no records at all (a 2023 Defender at age 5, when the new
  # model is only four years old) still gets this model's own difference from the average.
  class DefectOdds
    SMOOTHING = 50              # k: acts like 50 extra tests at the adjusted average rate
    ENGINE_MIN_TESTS = 200      # below this, pool all engines of the model
    BASELINE_MIN_TESTS = 30
    NEAR_YEARS = 3              # model records this close to the car's age measure r (keeps older generations out)
    RATIO_PRIOR = 10            # acts like 10 expected failures at 1x, so thin data keeps r near 1
    CELL_TRUST = 100            # below this many tests in the exact cell, the figure is partly an extrapolation

    Estimate = Data.define(:probability, :tests, :failures, :level)

    # How much to trust a figure, from the number of inspections behind it.
    def self.confidence_for(tests)
      if tests >= 500 then "high"
      elsif tests >= 100 then "medium"
      else "low"
      end
    end

    # near_age: the car's age today; model records within NEAR_YEARS of it set r. Nil uses every age.
    def initialize(make_key:, model_key:, engine_key: nil, near_age: nil)
      @engine_key = engine_key.presence
      @near_ages = near_age && ((near_age.floor - NEAR_YEARS)..(near_age.ceil + NEAR_YEARS))
      load_model(make_key, model_key)
      load_baselines
    end

    # tests is the evidence behind the figure: the exact cell's tests, or when that's thin, the model's
    # nearby tests capped below "high" confidence (the age trend then comes from the average car).
    def estimate(category_id, age:, band:)
      failures, tests, level = cell(category_id, age, band)
      prior = [ baseline(category_id, age, band) * model_ratio(category_id), 0.95 ].min
      evidence = tests >= CELL_TRUST ? tests : [ [ tests, near_tests ].max, 499 ].min
      Estimate.new(probability: (failures + SMOOTHING * prior) / (tests + SMOOTHING), tests: evidence, failures:, level:)
    end

    # How this model compares with the average car at ages near this car's: 2.0 means twice the failures.
    def model_ratio(category_id)
      @ratios ||= {}
      @ratios[category_id] ||= begin
        observed = expected = 0.0
        near_cells.each do |(age, band), tests|
          observed += @model_rates[[ age, band, category_id ]]
          expected += tests * baseline(category_id, age, band)
        end
        (observed + RATIO_PRIOR) / (expected + RATIO_PRIOR)
      end
    end

    def model_tests = @model_cells.values.sum
    def model_has_data? = model_tests.positive?

    private
      def near_cells = @near_cells ||= @model_cells.select { |(age, _), _| @near_ages.nil? || @near_ages.cover?(age) }
      def near_tests = @near_tests ||= near_cells.values.sum

      def cell(category_id, age, band)
        if @engine_key
          tests = @cells[[ @engine_key, age, band ]].to_i
          return [ @rates[[ @engine_key, age, band, category_id ]].to_i, tests, :engine ] if tests >= ENGINE_MIN_TESTS
        end
        tests = @model_cells[[ age, band ]].to_i
        [ @model_rates[[ age, band, category_id ]].to_i, tests, tests.zero? ? :segment : :model ]
      end

      def baseline(category_id, age, band)
        tests = @band_tests[[ age, band ]].to_i
        return @baseline_failures[[ category_id, age, band ]].to_f / tests if tests >= BASELINE_MIN_TESTS
        @overall.fetch(category_id, 0.0)
      end

      def load_model(make_key, model_key)
        @cells = {}
        @model_cells = Hash.new(0)
        InspectionCell.where(make_key:, model_key:).pluck(:engine_key, :age_years, :mileage_band, :tests).each do |engine, age, band, tests|
          @cells[[ engine, age, band ]] = tests
          @model_cells[[ age, band ]] += tests
        end

        @rates = {}
        @model_rates = Hash.new(0)
        DefectRate.where(make_key:, model_key:)
          .pluck(:engine_key, :age_years, :mileage_band, :defect_category_id, :failures)
          .each do |engine, age, band, category_id, failures|
            @rates[[ engine, age, band, category_id ]] = failures
            @model_rates[[ age, band, category_id ]] += failures
          end
      end

      def load_baselines
        @band_tests = InspectionCell.group(:age_years, :mileage_band).sum(:tests)
        @baseline_failures = {}
        failures_by_category = Hash.new(0)
        DefectBaseline.pluck(:defect_category_id, :age_years, :mileage_band, :failures).each do |category_id, age, band, failures|
          @baseline_failures[[ category_id, age, band ]] = failures
          failures_by_category[category_id] += failures
        end
        all_tests = @band_tests.values.sum
        @overall = all_tests.zero? ? {} : failures_by_category.transform_values { |failures| failures.to_f / all_tests }
      end
  end
end
