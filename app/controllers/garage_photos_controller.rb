# Adds photos to a garage car's 360° spin (in the order chosen), or takes one out.
class GaragePhotosController < ApplicationController
  before_action { @car = Current.user.garage_cars.find(params[:garage_car_id]) }
  rate_limit to: 20, within: 1.minute, only: :create, with: -> { redirect_to garage_car_path(params[:garage_car_id]), alert: "Slow down a moment, then try again." }

  def create
    files = Array(params[:photos]).compact_blank
    return redirect_to(garage_car_path(@car), alert: "Choose some photos first.") if files.empty?
    return redirect_to(garage_car_path(@car), alert: "Photos must be JPEG, PNG or WebP pictures.") unless files.all? { GarageCar.picture?(_1) }

    @car.photos.attach(files)
    if @car.valid?
      redirect_to garage_car_path(@car), notice: "#{helpers.pluralize(files.size, "photo")} added."
    else
      # Attaching saves straight away, so take back the new ones that broke the rules.
      ActiveStorage::Attachment.where(record: @car, name: "photos").order(id: :desc).limit(files.size).each(&:purge)
      redirect_to garage_car_path(@car), alert: @car.errors.full_messages.to_sentence
    end
  end

  def destroy
    @car.photos.attachments.find(params[:id]).purge
    redirect_to garage_car_path(@car), notice: "Photo removed."
  end
end
