class User < ApplicationRecord
  CAR_TYPES = %w[sedan suv truck sport hatchback minivan wagon electric].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :usage_events, dependent: :delete_all
  has_many :garage_cars, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :first_name, :last_name, with: ->(name) { name.squish }
  normalizes :postal_code, with: ->(code) { code.strip.upcase.presence }
  normalizes :country, with: ->(code) { code.presence }
  normalizes :car_types, with: ->(types) { types.compact_blank.uniq }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  # Asked at sign-up and on the account page. Accounts made before names were asked keep working
  # (a password reset still saves) until the person next edits their details.
  validates :first_name, :last_name, presence: true, length: { maximum: 60 }, on: %i[create profile]
  validates :country, inclusion: { in: Market.codes }, allow_nil: true
  validates :postal_code, length: { maximum: 12 }, format: { with: /\A[A-Z0-9 -]+\z/ }, allow_nil: true
  validate :known_car_types

  def name = [ first_name, last_name ].compact_blank.join(" ").presence
  def initial = (first_name.presence || email_address).first.upcase

  # The shop-rate region their postcode is in, when we can tell.
  def region = country && LaborRate.region_for(country:, postal_code:)

  # ---- Plan and usage ----

  def plan_details = Plan.find(plan)
  def paid? = plan_details.paid?

  def used_this_month(kind) = usage_events.this_month.where(kind: kind.to_s).count

  # How many are left this month; nil when there's no limit (the plan has none, or billing is switched off).
  def remaining(kind)
    return unless Billing.enabled?
    limit = plan_details.limit(kind) or return
    [ limit - used_this_month(kind), 0 ].max
  end

  def can_use?(kind) = remaining(kind).nil? || remaining(kind).positive?

  def record_use!(kind, report: nil) = usage_events.create!(kind: kind.to_s, report:)

  private
    def known_car_types
      errors.add(:car_types, "has a type we don't know") if (car_types - CAR_TYPES).any?
    end
end
