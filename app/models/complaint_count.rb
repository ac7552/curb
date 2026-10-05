# NHTSA owner complaints counted per make, model, model year and part (see Importers::NhtsaComplaints).
class ComplaintCount < ApplicationRecord
  def average_miles = with_miles.positive? ? (miles_total.to_f / with_miles).round(-3).to_i : nil
end
