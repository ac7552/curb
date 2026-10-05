module PlansHelper
  CAR_TYPE_LABELS = { "suv" => "SUV" }.freeze

  def plan_price(plan, interval) = number_to_currency(plan.price_cents(interval) / 100.0)

  # How much a year costs less than twelve months, as a whole percent.
  def yearly_saving(plan)
    monthly = plan.price_cents("month") * 12
    number_to_percentage((monthly - plan.price_cents("year")) * 100.0 / monthly, precision: 0)
  end

  # "2 of 3 checks left this month", or "Unlimited checks".
  def plan_usage_line(user)
    left = user.remaining(:check)
    return "Unlimited checks" if left.nil?
    "#{left} of #{user.plan_details.limit(:check)} free checks left this month"
  end

  def car_type_label(type) = CAR_TYPE_LABELS.fetch(type) { type.capitalize }
end
