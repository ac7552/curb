# Features that can be switched on and off from the admin panel, without a deploy. A switch an admin has
# flipped (FeatureFlag) wins; until then it has its default. Read fresh each time: it's a tiny table, and a
# switch then takes effect on the very next page.
class Feature
  Definition = Data.define(:key, :name, :description, :default)

  ALL = [
    Definition.new(
      key: "billing", name: "Plans and payments",
      description: "The Plus plan, payment pages and the monthly limit on checks. Off: nobody is limited, and checks " \
                   "are still counted. Needs Stripe set up first (docs/billing.md).",
      # CURB_BILLING sets the default, for a machine with no admin yet.
      default: -> { ActiveModel::Type::Boolean.new.cast(ENV.fetch("CURB_BILLING", "off")) }
    ),
    Definition.new(
      key: "insurance_estimate", name: "Insurance estimate",
      description: "A sample yearly insurance price in each US report, from the insurance calculator. Its rates are " \
                   "illustrative and car-specific claims data isn't loaded yet, so it's off; admins see it as a preview.",
      default: -> { false }
    )
  ].index_by(&:key).freeze

  def self.keys = ALL.keys
  def self.all = ALL.values
  def self.find(key) = ALL.fetch(key.to_s)

  def self.enabled?(key)
    definition = find(key)
    states.fetch(definition.key) { definition.default.call }
  end

  # Whether an admin has set it (rather than it running on its default).
  def self.set?(key) = states.key?(key.to_s)

  def self.set!(key, enabled, by: nil)
    flag = FeatureFlag.find_or_initialize_by(key: find(key).key)
    flag.update!(enabled:, updated_by: by)
    flag
  end

  def self.states = FeatureFlag.pluck(:key, :enabled).to_h
end
