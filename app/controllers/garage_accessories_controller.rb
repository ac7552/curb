# Products an owner is trying on their car. Paste a link: Curb reads the product's name, price and picture from the
# page (ProductPage). Shops that block that get a form to type the name and upload the picture instead.
class GarageAccessoriesController < ApplicationController
  before_action { @car = Current.user.garage_cars.find(params[:garage_car_id]) }
  before_action :set_accessory, only: %i[update destroy]
  rate_limit to: 15, within: 1.minute, only: :create, with: -> { redirect_to garage_car_path(params[:garage_car_id]), alert: "Slow down a moment, then try again." }

  def create
    @accessory = @car.accessories.new(accessory_params.except(:image))
    upload = accessory_params[:image]
    if upload.present?
      return redirect_to(garage_car_path(@car), alert: "The picture must be a JPEG, PNG or WebP.") unless GarageCar.picture?(upload)
      @accessory.image.attach(upload)
    end
    fill_in_from_page if @accessory.title.blank? || !@accessory.image.attached?

    if @accessory.save
      redirect_to garage_car_path(@car, anchor: "accessories"), notice: added_notice
    else
      redirect_to garage_car_path(@car, anchor: "accessories", accessory_url: @accessory.url), alert: problem
    end
  end

  # Only the "hide white background" switch changes after adding.
  def update
    @accessory.update!(remove_background: params.dig(:garage_accessory, :remove_background) == "1")
    redirect_to garage_car_path(@car, anchor: "accessories")
  end

  def destroy
    @accessory.destroy
    redirect_to garage_car_path(@car, anchor: "accessories"), notice: "#{@accessory.title} removed."
  end

  private
    def set_accessory
      @accessory = @car.accessories.find(params[:id])
    end

    def accessory_params = params.expect(garage_accessory: %i[url title price image])

    def fill_in_from_page
      details = ProductPage.read(@accessory.url) or return
      @accessory.title = details.title if @accessory.title.blank?
      @accessory.price ||= details.price
      if !@accessory.image.attached? && details.image_url && (image = ProductPage.download_image(details.image_url))
        @accessory.image.attach(image)
      end
    end

    def added_notice
      return "#{@accessory.title} added. Turn the car to a photo and place it." if @accessory.image.attached?
      "#{@accessory.title} added, but we couldn't get its picture. Remove it and add it again with a picture to place it."
    end

    def problem
      return "We couldn't read that page (some shops block it). Type the product's name and add its picture." if @accessory.errors.include?(:title)
      @accessory.errors.full_messages.to_sentence
    end
end
