# A plan from config/plans.yml: its name, prices and monthly limits.
class Plan
  KINDS = %w[check deep_check question].freeze
  INTERVALS = %w[month year].freeze

  attr_reader :key, :name

  def self.all
    @all ||= YAML.load_file(Rails.root.join("config/plans.yml")).to_h { |key, data| [ key, new(key, data.deep_symbolize_keys) ] }
  end
  def self.find(key) = all.fetch(key.to_s) { all.fetch("free") }
  def self.free = find("free")
  def self.paid = all.values.select(&:paid?)

  def initialize(key, data)
    @key = key
    @name = data[:name]
    @prices = data.fetch(:prices, {}).transform_keys(&:to_s)
    @limits = data.fetch(:limits).transform_keys(&:to_s)
  end

  # How many a month; nil for no limit.
  def limit(kind) = @limits.fetch(kind.to_s)
  def unlimited?(kind) = limit(kind).nil?
  def includes?(kind) = unlimited?(kind) || limit(kind).positive?

  def paid? = @prices.any?
  def price_cents(interval) = @prices.fetch(interval.to_s)

  # Stripe's ID for this plan's price, from credentials (or STRIPE_PRICE_PLUS_MONTH and so on).
  def stripe_price_id(interval)
    ENV["STRIPE_PRICE_#{key.upcase}_#{interval.to_s.upcase}"].presence ||
      Rails.application.credentials.dig(:stripe, :prices, :"#{key}_#{interval}")
  end

  # The plan a Stripe price belongs to, for webhooks.
  def self.for_stripe_price(price_id)
    paid.find { |plan| INTERVALS.any? { |interval| plan.stripe_price_id(interval) == price_id } }
  end
end
