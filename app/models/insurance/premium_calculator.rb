# Illustrative auto insurance premium model.
#
#   premium(coverage) = base_rate × territory × driver × HLDI vehicle factor × deductible/limit factor
#   total             = sum of coverages × (1 - discounts), floored at a minimum
#
# All base rates and factor tables are ILLUSTRATIVE, not any insurer's real numbers, which is why reports only show
# this to admins until the "insurance_estimate" feature is switched on. HLDI indexes (100 = average vehicle) become
# vehicle factors via index / 100; a missing index counts as average.
module Insurance
  class PremiumCalculator
    # Annual base rates per coverage for an "average" driver, vehicle and territory.
    BASE_RATES = {
      bodily_injury: 450.0,
      property_damage: 380.0,
      pip: 120.0,
      uninsured: 110.0,
      collision: 520.0,
      comprehensive: 210.0
    }.freeze

    # Which HLDI index drives each coverage's vehicle factor.
    HLDI_MAP = {
      bodily_injury: :injury,
      property_damage: :collision, # proxy when no property damage liability index is supplied
      pip: :injury,
      uninsured: :injury,
      collision: :collision,
      comprehensive: :theft
    }.freeze

    AGE_FACTORS = [
      [ 16..19, 2.60 ], [ 20..24, 1.65 ], [ 25..29, 1.15 ], [ 30..59, 1.00 ],
      [ 60..69, 1.05 ], [ 70..120, 1.25 ]
    ].freeze

    DEDUCTIBLE_FACTORS = { 250 => 1.15, 500 => 1.00, 1000 => 0.85, 2000 => 0.70 }.freeze

    # Liability limit multipliers (per person / per accident / property). Texas minimum = 30/60/25.
    LIMIT_FACTORS = {
      "30/60/25" => 1.00,
      "50/100/50" => 1.20,
      "100/300/100" => 1.45,
      "250/500/100" => 1.70
    }.freeze

    DISCOUNTS = {
      bundle: 0.10,
      multi_car: 0.08,
      paid_in_full: 0.05,
      good_student: 0.08,
      defensive_course: 0.05,
      telematics: 0.10
    }.freeze

    CREDIT_FACTORS = { excellent: 0.85, good: 1.00, fair: 1.20, poor: 1.55 }.freeze

    MAX_TOTAL_DISCOUNT = 0.35
    MINIMUM_PREMIUM = 400.0

    attr_reader :vehicle, :driver, :options

    # vehicle: { name:, hldi: { injury:, collision:, theft:, property_damage: (optional) } }
    # driver:  { age:, accidents:, violations:, credit_tier: :excellent/:good/:fair/:poor, married: }
    # options: { territory_factor:, deductible:, limits:, coverages: [...], discounts: [...], annual_miles: }
    def initialize(vehicle:, driver:, options: {})
      @vehicle = vehicle
      @driver = driver
      @options = {
        territory_factor: 1.0,
        deductible: 500,
        limits: "30/60/25",
        coverages: BASE_RATES.keys,
        discounts: [],
        annual_miles: 12_000
      }.merge(options)
      validate!
    end

    def breakdown
      @breakdown ||= options[:coverages].to_h do |coverage|
        [ coverage, (BASE_RATES.fetch(coverage) * territory_factor * driver_factor * vehicle_factor(coverage) * coverage_factor(coverage)).round(2) ]
      end
    end

    def subtotal = breakdown.values.sum.round(2)

    def discount_rate = [ options[:discounts].sum { |discount| DISCOUNTS.fetch(discount) }, MAX_TOTAL_DISCOUNT ].min

    def total = [ (subtotal * (1 - discount_rate)).round(2), MINIMUM_PREMIUM ].max

    def monthly = (total / 12.0).round(2)

    def vehicle_factor(coverage)
      hldi = vehicle.fetch(:hldi)
      key = coverage == :property_damage && hldi[:property_damage] ? :property_damage : HLDI_MAP.fetch(coverage)
      index = hldi[key] or return 1.0 # missing index => treat as average
      index / 100.0
    end

    def driver_factor = age_factor * record_factor * credit_factor * marital_factor * mileage_factor

    # Whether any of the car's own claims indexes went in, rather than every coverage counting it as average.
    def vehicle_known? = vehicle.fetch(:hldi).values.any?

    private
      def territory_factor = options[:territory_factor]

      def age_factor
        AGE_FACTORS.find { |range, _| range.cover?(driver.fetch(:age)) }&.last or raise ArgumentError, "unsupported age #{driver[:age]}"
      end

      # Each at-fault accident +35%, each violation +20%, compounding.
      def record_factor = (1.35**driver.fetch(:accidents, 0)) * (1.20**driver.fetch(:violations, 0))

      def credit_factor = CREDIT_FACTORS.fetch(driver.fetch(:credit_tier, :good))

      def marital_factor = driver[:married] ? 0.95 : 1.00

      def mileage_factor
        miles = options[:annual_miles]
        if miles < 7_500 then 0.90
        elsif miles <= 15_000 then 1.00
        else 1.10
        end
      end

      def coverage_factor(coverage)
        case coverage
        when :collision, :comprehensive then DEDUCTIBLE_FACTORS.fetch(options[:deductible])
        when :bodily_injury, :property_damage, :uninsured then LIMIT_FACTORS.fetch(options[:limits])
        else 1.0
        end
      end

      def validate!
        raise ArgumentError, "vehicle needs :hldi indexes" unless vehicle[:hldi].is_a?(Hash)
        unknown = options[:coverages] - BASE_RATES.keys
        raise ArgumentError, "unknown coverages: #{unknown}" if unknown.any?
        bad = options[:discounts] - DISCOUNTS.keys
        raise ArgumentError, "unknown discounts: #{bad}" if bad.any?
        DEDUCTIBLE_FACTORS.fetch(options[:deductible]) { raise ArgumentError, "deductible must be one of #{DEDUCTIBLE_FACTORS.keys}" }
        LIMIT_FACTORS.fetch(options[:limits]) { raise ArgumentError, "limits must be one of #{LIMIT_FACTORS.keys}" }
      end
  end
end
