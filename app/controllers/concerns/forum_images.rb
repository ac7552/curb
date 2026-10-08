# Pictures attached to a thread or reply: real JPEG, PNG or WebP files only (checked from their bytes), at most 4.
module ForumImages
  extend ActiveSupport::Concern

  private
    def attach_images(record)
      files = Array(params.dig(record.model_name.param_key, :images)).compact_blank
      return true if files.empty?
      return record.errors.add(:images, "must be JPEG, PNG or WebP pictures") && false unless files.all? { GarageCar.picture?(_1) }
      record.images.attach(files)
      true
    end
end
