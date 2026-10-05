# Inserts inspections straight into the tables behind the defect-rate views.
module InspectionData
  def add_inspections(make_key:, model_key:, count:, failures:, category:, engine_key: nil, age: 5, mileage: 45_000)
    first_used = Date.new(2015, 1, 1)
    @inspection_seq ||= 0
    vehicles = Array.new(count) do
      @inspection_seq += 1
      { source: "test", external_id: "v#{@inspection_seq}", country: "GB", make: make_key, model: model_key,
        make_key:, model_key:, engine_key:, first_used_on: first_used }
    end
    vehicle_ids = Vehicle.insert_all!(vehicles, returning: :id).rows.flatten
    inspections = vehicle_ids.map do |vehicle_id|
      { vehicle_id:, source: "test", external_id: "i#{vehicle_id}", inspected_on: first_used + (age * 365.25 + 30).round,
        mileage:, result: "pass" }
    end
    inspection_ids = Inspection.insert_all!(inspections, returning: :id).rows.flatten
    phrase = DefectPhrase.find_or_create_by!(source: "test", external_id: category.slug, text: category.name, defect_category: category)
    Defect.insert_all!(inspection_ids.first(failures).map { |id| { inspection_id: id, defect_phrase_id: phrase.id, kind: "fail" } }) if failures.positive?
  end

  def refresh_rates = DefectRate.refresh_all!(concurrently: false)
end
