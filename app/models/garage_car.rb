# A car someone owns, in their garage. Only its owner sees it. Its photos, taken walking around the car in order,
# make the 360° spin; accessories are products placed on those photos.
class GarageCar < ApplicationRecord
  MAX_PHOTOS = 36
  MAX_PHOTO_BYTES = 15.megabytes
  PHOTO_TYPES = %w[image/jpeg image/png image/webp].freeze

  belongs_to :user
  has_many :accessories, class_name: "GarageAccessory", dependent: :destroy
  has_many_attached :photos

  normalizes :make, :model, :nickname, with: ->(value) { value.squish.presence }

  validates :make, :model, presence: true, length: { maximum: 60 }
  validates :model_year, numericality: { only_integer: true, greater_than_or_equal_to: 1950, less_than_or_equal_to: -> { Date.current.year + 1 } }
  validates :nickname, length: { maximum: 60 }
  validate :photos_fit

  def make_key = VehicleName.make_key(make)
  def model_key = VehicleName.model_key(model)
  def title = "#{model_year} #{VehicleName.display(make:, model:)}"
  def name = nickname || title

  # The photos in the order they go around the car.
  def spin_photos = photos.attachments.order(:id)

  # Whether a file really is a JPEG, PNG or WebP picture, from its first bytes rather than its name.
  def self.picture?(file)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    head = io.read(12).to_s.b
    io.rewind
    head.start_with?("\xFF\xD8\xFF".b) || head.start_with?("\x89PNG\r\n\x1A\n".b) || (head.start_with?("RIFF") && head[8, 4] == "WEBP")
  end

  private
    def photos_fit
      errors.add(:photos, "can be at most #{MAX_PHOTOS}") if photos.attachments.size > MAX_PHOTOS
      photos.attachments.each do |photo|
        errors.add(:photos, "must be JPEG, PNG or WebP pictures") unless PHOTO_TYPES.include?(photo.blob.content_type)
        errors.add(:photos, "must each be under #{MAX_PHOTO_BYTES / 1.megabyte} MB") if photo.blob.byte_size > MAX_PHOTO_BYTES
      end
    end
end
