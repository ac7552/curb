module MaintenanceGuides
  # One maker's document with the maintenance schedule for a year and model: where it is, what to call it
  # when cited, and what kind of document it is, which tells the reader where to look:
  #   :maintenance_guide   a guide that is all schedule (Toyota, Lexus, Honda, Mazda)
  #   :owner_manual        a 400–600 page owner's manual with a schedule chapter (Nissan, GM, Hyundai)
  #   :all_models_booklet  one booklet for every model that year (Porsche, Subaru)
  #   :nhtsa_filing        a schedule the maker filed with NHTSA (VW, Audi)
  Guide = Data.define(:make, :model, :model_year, :url, :title, :kind) do
    def initialize(kind: :maintenance_guide, **rest) = super(kind:, **rest)
  end
end
