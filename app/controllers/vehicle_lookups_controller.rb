# Decodes a VIN or plate for the new-check form.
class VehicleLookupsController < ApplicationController
  rate_limit to: 30, within: 1.minute

  # The models of one make for the new-check form, most common first.
  def models
    country = Market.codes.include?(params[:country]) ? params[:country] : "US"
    year = params[:year].to_s[/\A\d{4}\z/]
    render json: MakeCatalog.models(make: params[:make].to_s, country:, year:)
  end

  def show
    match = if params[:vin].present?
      VehicleLookup.by_vin(params[:vin].to_s.strip.upcase)
    else
      VehicleLookup.by_plate(params[:plate].to_s.upcase.gsub(/[^A-Z0-9]/, ""), country: params[:country].to_s.upcase)
    end

    if match
      render json: match.as_json.except(:history)
    else
      render json: { error: "We couldn't find that car. Check it, or enter the make and model." }, status: :not_found
    end
  rescue VehicleLookup::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue HttpClient::Error
    render json: { error: "The lookup service isn't responding. Enter the make and model instead." }, status: :bad_gateway
  end
end
