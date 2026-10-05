# What goes wrong on any make, model and year, without checking a particular car.
class ModelProfilesController < ApplicationController
  def show
    @make, @model, @year = params[:make].to_s.strip, params[:model].to_s.strip, params[:year].to_i
    return unless @make.present? && @model.present? && @year.between?(1995, Date.current.year + 1)

    engine_key = VehicleName.engine_key(liters: params[:engine].to_s[/\d+(\.\d+)?/]&.to_f, fuel: params[:fuel])
    @profile = ModelProfile.for(make: @make, model: @model, model_year: @year, engine_key:)
  end
end
