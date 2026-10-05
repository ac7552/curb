class LaborRate < ApplicationRecord
  SHOP_TYPES = %w[independent dealer].freeze

  validates :country, :region, presence: true
  validates :shop_type, inclusion: { in: SHOP_TYPES }
  validates :hourly_rate, numericality: { greater_than: 0 }

  def self.regions_for(country) = where(country:).group(:region).order(Arel.sql("MIN(id)")).pluck(:region)

  # The rate region a postcode falls in, roughly: US ZIP codes by their first digit (which follows the map
  # from the Northeast west), UK postcodes by area letters, Dutch postcodes by number. nil when unsure.
  US_ZIP_REGIONS = { "0" => "Northeast", "1" => "Northeast", "2" => "South", "3" => "South", "4" => "Midwest",
                     "5" => "Midwest", "6" => "Midwest", "7" => "South", "8" => "West", "9" => "West" }.freeze
  LONDON_AREAS = %w[E EC N NW SE SW W WC].freeze
  SOUTH_EAST_AREAS = %w[BN CT GU HP ME MK OX PO RG RH SL SO TN].freeze

  def self.region_for(country:, postal_code:)
    code = postal_code.to_s.upcase.delete(" ")
    return if code.empty?

    region = case country
    when "US" then US_ZIP_REGIONS[code[0]] if code.match?(/\A\d{5}/)
    when "GB"
      area = code[/\A[A-Z]{1,2}/]
      if LONDON_AREAS.include?(area) then "London"
      elsif SOUTH_EAST_AREAS.include?(area) then "South East"
      elsif area then "Rest of UK"
      end
    when "NL" then (code.to_i.between?(1000, 3999) ? "Randstad" : "Rest of Netherlands") if code.match?(/\A\d{4}/)
    end
    region if region && regions_for(country).include?(region)
  end

  def self.rate_for(country:, region:, shop_type:)
    find_by(country:, region:, shop_type:)&.hourly_rate ||
      where(country:, shop_type:).average(:hourly_rate) ||
      raise(ActiveRecord::RecordNotFound, "No labor rate for #{country}")
  end
end
