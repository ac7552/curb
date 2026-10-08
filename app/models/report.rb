# A buyer's check of one car: their inputs, what the live lookup found, and the calculated numbers.
# Distances are stored in miles; the form works in the market's own unit (km in the Netherlands).
class Report < ApplicationRecord
  LOOKUP_MODES = %w[vin plate model].freeze
  ADDON_WARRANTIES = %w[none cpo extended].freeze
  ADDON_COVERAGES = %w[powertrain comprehensive].freeze

  belongs_to :user
  has_secure_token :share_token

  attribute :odometer, :integer
  attribute :yearly_distance, :integer

  normalizes :vin, with: ->(vin) { vin.strip.upcase.presence }
  normalizes :plate, with: ->(plate) { plate.upcase.gsub(/[^A-Z0-9]/, "").presence }

  before_validation :convert_distances

  validates :country, inclusion: { in: Market.codes }
  validates :lookup_mode, inclusion: { in: LOOKUP_MODES }
  validates :make, :model, :region, presence: true
  validates :model_year, numericality: { only_integer: true, in: 1980..(Date.current.year + 1) }
  validates :current_mileage, numericality: { only_integer: true, in: 0..500_000 }
  validates :asking_price, numericality: { greater_than: 0 }
  validates :ownership_years, numericality: { only_integer: true, in: 1..10 }
  validates :miles_per_year, numericality: { only_integer: true, in: 500..60_000 }
  validates :addon_warranty, inclusion: { in: ADDON_WARRANTIES }
  validates :shop_type, inclusion: { in: LaborRate::SHOP_TYPES }
  validates :monthly_budget, :emergency_savings, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  with_options unless: -> { addon_warranty == "none" } do
    validates :addon_years, numericality: { only_integer: true, in: 1..10 }
    validates :addon_coverage, inclusion: { in: ADDON_COVERAGES }
  end
  validates :vin, length: { is: 17 }, format: { with: /\A[A-HJ-NPR-Z0-9]+\z/, message: "can't contain I, O or Q" }, if: -> { lookup_mode == "vin" }
  validates :plate, presence: true, if: -> { lookup_mode == "plate" }

  validate :car_exists, if: -> { self.class.check_cars_exist && make.present? && model.present? && model_year.present? }

  # Checks typed cars against NHTSA's model list (off in tests, which never reach the network).
  class_attribute :check_cars_exist, default: true

  scope :recent, -> { order(created_at: :desc) }

  def market = Market.fetch(country)
  def make_key = VehicleName.make_key(make)
  # The spelling of the model with the most inspection data, so "C-Class" finds the UK "C" records.
  def model_key
    @model_key ||= begin
      candidates = VehicleName.model_key_candidates(make, model)
      tests = InspectionCell.where(make_key:, model_key: candidates).group(:model_key).sum(:tests)
      candidates.max_by { |key| tests.fetch(key, 0) }
    end
  end
  def engine_key = VehicleName.engine_key(liters: engine.to_s[/\d+(\.\d+)?/]&.to_f, fuel: fuel_type)
  def title = "#{model_year} #{VehicleName.display(make:, model:)}"
  def calculated? = calculated_at.present?

  def result = @result ||= results.deep_symbolize_keys
  def live = @live ||= live_data.deep_symbolize_keys

  def odometer_in_unit = Market.from_miles(current_mileage, country)
  def yearly_distance_in_unit = Market.from_miles(miles_per_year, country)

  def labor_rate = LaborRate.rate_for(country:, region:, shop_type:)

  # A sample insurance price for this car (Insurance::PremiumCalculator), US only: an average driver (35, clean record,
  # good credit) with full coverage and a $500 deductible, at the miles this buyer drives. The car's claims indexes
  # come in when we have them; until then it counts as an average car.
  STANDARD_DRIVER = { age: 35, accidents: 0, violations: 0, credit_tier: :good, married: false }.freeze

  def insurance_estimate
    return unless country == "US"
    index = InsuranceLossIndex.for(make_key:, model_key:, model_year:)
    Insurance::PremiumCalculator.new(
      vehicle: { name: title, hldi: index&.to_hldi || {} }, driver: STANDARD_DRIVER,
      options: { annual_miles: miles_per_year || market.default_miles_per_year }
    )
  end

  # Recalls confirmed open on this exact car mean the buyer pays nothing for that part. NHTSA's
  # model-level list doesn't say whether a recall is still open on a VIN, so those are only flagged.
  def recall_category_ids
    slugs = Array(live[:recalls]).select { |recall| recall[:open_on_vehicle] }.filter_map { |recall| recall[:category] }
    DefectCategory.where(slug: slugs).ids
  end

  def model_recall_slugs = Array(live[:recalls]).filter_map { |recall| recall[:category] }.uniq

  def calculator_inputs(as_of: Date.current)
    TrueCost::Inputs.new(
      market:, make_key:, model_key:, engine_key:, model_year:, first_used_on:, as_of:,
      mileage: current_mileage, price: asking_price, years: ownership_years, miles_per_year:,
      labor_rate: labor_rate.to_f, addon_warranty:, addon_years:, addon_miles: addon_miles_in_miles,
      addon_coverage:, emergency_savings: emergency_savings&.to_f, monthly_budget: monthly_budget&.to_f,
      recall_category_ids:
    )
  end

  def calculate!(as_of: Date.current)
    @result = nil
    results = TrueCost::Calculator.new(calculator_inputs(as_of:)).call
    results[:data][:demo] = Vehicle.exists?(source: Importers::MotBulk::DEMO_SOURCE)
    update!(results:, calculated_at: Time.current)
  end

  private
    # "2020 Tesla Cybertruck" and made-up names get stopped here, with the real models as suggestions.
    # When NHTSA can't be reached the check is skipped rather than blocking the buyer.
    def car_exists
      models = Nhtsa::Vpic.new.models(make:, model_year:)
      if models.empty?
        errors.add(:base, "\"#{make}\" didn't make cars in #{model_year}, as far as we can tell. Check the spelling or the year.")
      elsif !Nhtsa::Vpic.listed?(make:, model:, models:)
        errors.add(:base, "\"#{model}\" isn't a #{model_year} #{VehicleName.display_make(make)}. Try: #{models.first(8).join(", ")}.")
      end
    rescue HttpClient::Error
      nil
    end

    def convert_distances
      self.current_mileage = Market.to_miles(odometer, country) if odometer.present?
      self.miles_per_year = Market.to_miles(yearly_distance, country) if yearly_distance.present?
      self.miles_per_year ||= market.default_miles_per_year
    end

    def addon_miles_in_miles = Market.to_miles(addon_miles, country)
end
