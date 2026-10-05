module TrueCost
  # Everything the calculator needs, already converted to miles and the buyer's currency.
  Inputs = Data.define(
    :market, :make_key, :model_key, :engine_key, :model_year, :first_used_on, :as_of,
    :mileage, :price, :years, :miles_per_year, :labor_rate,
    :addon_warranty, :addon_years, :addon_miles, :addon_coverage,
    :emergency_savings, :monthly_budget, :recall_category_ids
  ) do
    def age_now
      in_service = first_used_on || Date.new(model_year, 7, 1)
      [ (as_of - in_service).to_f / 365.25, 0.0 ].max
    end

    # Car age and odometer halfway through ownership year t (1-based).
    def age_in_year(t) = (age_now + t - 0.5).floor
    def mileage_in_year(t) = (mileage + miles_per_year * (t - 0.5)).round
  end
end
