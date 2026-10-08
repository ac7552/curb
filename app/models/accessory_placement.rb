# Where an accessory sits on one photo of a car's spin. Position and size are fractions of the photo, so they hold
# at any screen size: x and y are the accessory's centre, width its width; rotation is in degrees.
class AccessoryPlacement < ApplicationRecord
  belongs_to :garage_accessory
  belongs_to :photo, class_name: "ActiveStorage::Attachment"

  validates :x, :y, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :width, numericality: { greater_than: 0.01, less_than_or_equal_to: 1.5 }
  validates :rotation, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validate :photo_is_the_cars

  private
    def photo_is_the_cars
      car = garage_accessory&.garage_car
      errors.add(:photo, "isn't one of this car's photos") unless car && photo && photo.record == car && photo.name == "photos"
    end
end
