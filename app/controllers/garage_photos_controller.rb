# Adds photos to a garage car's 360° spin (in the order chosen), or takes one out. A walk-around (replace=1) swaps
# out the photos already there, so the spin is one smooth loop.
class GaragePhotosController < ApplicationController
  before_action { @car = Current.user.garage_cars.find(params[:garage_car_id]) }
  rate_limit to: 20, within: 1.minute, only: :create, with: -> { redirect_to garage_car_path(params[:garage_car_id]), alert: "Slow down a moment, then try again." }

  def create
    files = Array(params[:photos]).compact_blank
    replacing = params[:replace] == "1"
    problem = problem_with(files, replacing:)
    return redirect_to(garage_car_path(@car), alert: problem) if problem

    # Checked first, then swapped in one transaction: the old photos are unlinked, the new ones attached, and only once
    # they're saved are the old files deleted. If anything fails, the old spin is left as it was.
    earlier = replacing ? @car.photos.attachments.to_a : []
    saved = ActiveRecord::Base.transaction do
      earlier.each(&:delete)
      @car.reload.photos.attach(files) or raise ActiveRecord::Rollback # attach gives nothing back when the save fails
      true
    end
    return redirect_to(garage_car_path(@car), alert: "Couldn't save those photos. Try again.") unless saved

    earlier.each { _1.blob.purge }
    redirect_to garage_car_path(@car), notice: replacing ? "Your 360° spin is ready." : "#{helpers.pluralize(files.size, "photo")} added."
  end

  def destroy
    @car.photos.attachments.find(params[:id]).purge
    redirect_to garage_car_path(@car), notice: "Photo removed."
  end

  private
    def problem_with(files, replacing:)
      kept = replacing ? 0 : @car.photos.attachments.size
      if files.empty? then "Choose some photos first."
      elsif kept + files.size > GarageCar::MAX_PHOTOS then "A spin can have at most #{GarageCar::MAX_PHOTOS} photos."
      elsif !files.all? { GarageCar.picture?(_1) } then "Photos must be JPEG, PNG or WebP pictures."
      elsif files.any? { _1.size > GarageCar::MAX_PHOTO_BYTES } then "Photos must each be under #{GarageCar::MAX_PHOTO_BYTES / 1.megabyte} MB."
      end
    end
end
