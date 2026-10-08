class User < ApplicationRecord
  CAR_TYPES = %w[sedan suv truck sport hatchback minivan wagon electric].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :usage_events, dependent: :delete_all
  has_many :garage_cars, dependent: :destroy
  has_many :forum_threads, dependent: :destroy
  has_many :forum_posts, dependent: :destroy
  has_many :forum_reports, foreign_key: :reporter_id, dependent: :destroy

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
  # How they appear in Our Garage: first name and last initial, never their full name or email.
  def forum_name = first_name.present? ? [ first_name, last_name.to_s.first.presence&.then { "#{_1}." } ].compact.join(" ") : "Member"
  def banned? = banned_at.present?
  def can_post? = !banned? && first_name.present? && last_name.present?

  # Stops them posting in Our Garage and hides everything they've posted there.
  def ban!
    now = Time.current
    transaction do
      update_column(:banned_at, now)
      forum_threads.where(hidden_at: nil).update_all(hidden_at: now)
      forum_posts.where(hidden_at: nil).update_all(hidden_at: now)
    end
  end

  def unban! = update_column(:banned_at, nil)
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
