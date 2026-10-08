# A product an owner is thinking of adding to their car, from a link they pasted. Its picture can be placed on the
# car's photos to see how it would look (AccessoryPlacement).
class GarageAccessory < ApplicationRecord
  MAX_IMAGE_BYTES = 8.megabytes

  belongs_to :garage_car
  has_many :placements, class_name: "AccessoryPlacement", dependent: :destroy
  has_one_attached :image

  normalizes :title, :price, with: ->(value) { value.squish.presence }

  validates :url, presence: true, length: { maximum: 2_000 }, format: { with: %r{\Ahttps?://\S+\z}i, message: "must be a web link" }
  validates :title, presence: true, length: { maximum: 200 }
  validates :price, length: { maximum: 40 }
  validate :image_is_a_picture

  # The shop's name from the link: "amazon.com".
  def store
    URI.parse(url).host.to_s.delete_prefix("www.")
  rescue URI::InvalidURIError
    ""
  end

  private
    def image_is_a_picture
      return unless image.attached?
      errors.add(:image, "must be a JPEG, PNG or WebP picture") unless GarageCar::PHOTO_TYPES.include?(image.blob.content_type)
      errors.add(:image, "must be under #{MAX_IMAGE_BYTES / 1.megabyte} MB") if image.blob.byte_size > MAX_IMAGE_BYTES
    end
end
