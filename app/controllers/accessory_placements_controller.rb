# Where an accessory sits on one photo of the spin. Saved from the editor as you drag, resize and turn it.
class AccessoryPlacementsController < ApplicationController
  before_action do
    car = Current.user.garage_cars.find(params[:garage_car_id])
    @accessory = car.accessories.find(params[:accessory_id])
  end

  def create
    placement = @accessory.placements.find_or_initialize_by(photo_id: params.require(:photo_id))
    placement.assign_attributes(x: 0.5, y: 0.5, width: 0.3, rotation: 0) if placement.new_record?
    if placement.save
      render json: placement_json(placement), status: :created
    else
      render json: { errors: placement.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    placement = @accessory.placements.find(params[:id])
    if placement.update(params.expect(placement: %i[x y width rotation]))
      render json: placement_json(placement)
    else
      render json: { errors: placement.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @accessory.placements.find(params[:id]).destroy
    head :no_content
  end

  private
    def placement_json(placement)
      placement.slice(:id, :photo_id).merge(x: placement.x.to_f, y: placement.y.to_f, width: placement.width.to_f, rotation: placement.rotation.to_f)
    end
end
