# What threads and replies share: votes (with a running score), up to 4 pictures, and reports.
module ForumContent
  extend ActiveSupport::Concern

  MAX_IMAGES = 4

  included do
    belongs_to :user
    has_many :votes, class_name: "ForumVote", as: :votable, dependent: :delete_all
    has_many :reports, class_name: "ForumReport", as: :reportable, dependent: :destroy
    has_many_attached :images

    validate :images_fit
  end

  def hidden? = hidden_at.present?

  private
    def images_fit
      errors.add(:images, "can be at most #{MAX_IMAGES}") if images.attachments.size > MAX_IMAGES
      images.attachments.each do |image|
        errors.add(:images, "must be JPEG, PNG or WebP pictures") unless GarageCar::PHOTO_TYPES.include?(image.blob.content_type)
        errors.add(:images, "must each be under #{GarageCar::MAX_PHOTO_BYTES / 1.megabyte} MB") if image.blob.byte_size > GarageCar::MAX_PHOTO_BYTES
      end
    end
end
