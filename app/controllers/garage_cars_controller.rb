# My Garage: the cars you own, each with a 360° spin from your photos and the accessories you're considering.
class GarageCarsController < ApplicationController
  before_action :set_car, only: %i[show edit update destroy]

  def index
    @cars = Current.user.garage_cars.order(:created_at).with_attached_photos
  end

  def show
    @photos = @car.spin_photos.includes(:blob)
    @accessories = @car.accessories.order(:created_at).with_attached_image.includes(:placements)
  end

  def new
    @car = Current.user.garage_cars.new(model_year: Date.current.year)
  end

  def create
    @car = Current.user.garage_cars.new(car_params)
    if @car.save
      redirect_to garage_car_path(@car), notice: "#{@car.name} is in your garage. Add photos walking around it for the 360° view."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @car.update(car_params)
      redirect_to garage_car_path(@car), notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @car.destroy
    redirect_to garage_cars_path, notice: "#{@car.name} is out of your garage."
  end

  private
    def set_car
      @car = Current.user.garage_cars.find(params[:id])
    end

    def car_params = params.expect(garage_car: %i[make model model_year nickname])
end
