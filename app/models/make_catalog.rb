# The makes and models the new-check form offers, most common first. The raw inspection catalog
# holds thousands of one-off spellings and kit cars ("A K SPORTSCARS", "0PEL"), so a make or model
# only shows up once enough real cars carry it.
module MakeCatalog
  mattr_accessor :min_make_tests, default: 5_000
  mattr_accessor :min_model_tests, default: 300
  MAX_MODELS = 40

  # Register names that are another make under a different badge.
  MERGED_MAKES = { "SMART (MCC)" => "SMART", "CHRYSLER-JEEP" => "JEEP", "LONDON TAXIS INT" => "LEVC" }.freeze
  NOT_MODELS = %w[UNCLASSIFIED UNKNOWN OTHER -].freeze

  # Simple Icons slugs (https://simpleicons.org). Makes missing here get a monogram instead.
  LOGOS = {
    "ACURA" => "acura", "ALFA ROMEO" => "alfaromeo", "ASTON MARTIN" => "astonmartin", "AUDI" => "audi",
    "BENTLEY" => "bentley", "BMW" => "bmw", "CADILLAC" => "cadillac", "CHEVROLET" => "chevrolet",
    "CHRYSLER" => "chrysler", "CITROEN" => "citroen", "DACIA" => "dacia", "DS" => "dsautomobiles",
    "FERRARI" => "ferrari", "FIAT" => "fiat", "FORD" => "ford", "HONDA" => "honda", "HYUNDAI" => "hyundai",
    "INFINITI" => "infiniti", "JAGUAR" => "jaguar", "JEEP" => "jeep", "KIA" => "kia", "LAMBORGHINI" => "lamborghini",
    "LAND ROVER" => "landrover", "MASERATI" => "maserati", "MAZDA" => "mazda", "MCLAREN" => "mclaren",
    "MERCEDES-BENZ" => "mercedes", "MG" => "mg", "MINI" => "mini", "MITSUBISHI" => "mitsubishi",
    "NISSAN" => "nissan", "OPEL" => "opel", "PEUGEOT" => "peugeot", "POLESTAR" => "polestar",
    "PORSCHE" => "porsche", "RAM" => "ram", "RENAULT" => "renault", "ROLLS ROYCE" => "rollsroyce",
    "SEAT" => "seat", "SKODA" => "skoda", "SMART" => "smart", "SUBARU" => "subaru", "SUZUKI" => "suzuki",
    "TESLA" => "tesla", "TOYOTA" => "toyota", "VAUXHALL" => "vauxhall", "VOLKSWAGEN" => "volkswagen", "VOLVO" => "volvo"
  }.freeze
  LOGO_URL = "https://cdn.jsdelivr.net/npm/simple-icons@v13/icons/%s.svg".freeze

  module_function

  def logo_url(make)
    slug = LOGOS[VehicleName.make_key(make)]
    format(LOGO_URL, slug) if slug
  end

  # [{ name: "Toyota", logo: "https://…" }, …] for a market, most common first. US makes are
  # ordered by new-car sales; elsewhere by how many of them were inspected.
  def makes(country)
    Rails.cache.fetch([ "make_catalog/makes/v1", country ], expires_in: 12.hours) do
      keys = country == "US" ? (us_sales_order + tested_makes.keys).uniq : tested_makes.keys
      keys.map { |key| { name: VehicleName.display_make(key), logo: logo_url(key) } }
    end
  end

  # Model names for a make, most common first. With a year, US lists come from NHTSA, the same list
  # a check is validated against, so every choice offered goes through.
  def models(make:, country:, year: nil)
    make_key = VehicleName.make_key(make)
    popular = popular_models(make_key, country)
    names = popular.map { |key| display_model(make_key, key) }.uniq
    return names unless country == "US" && year.present?

    listed = Nhtsa::Vpic.new.models(make:, model_year: year)
    return names if listed.empty?

    rank = popular.each_with_index.to_h
    listed.sort_by { |name| [ rank.fetch(VehicleName.model_key(name), rank.size), name ] }
  rescue HttpClient::Error
    names
  end

  # UK records call a C-Class "C" or "C-CLASS"; both read as "C-Class".
  def display_model(make_key, key)
    if make_key == "MERCEDES-BENZ" && (letters = key[/\A([A-Z])(-CLASS)?\z/, 1])
      "#{letters}-Class"
    else
      VehicleName.display_model(key)
    end
  end

  def popular_models(make_key, country)
    Rails.cache.fetch([ "make_catalog/models/v1", make_key, country ], expires_in: 12.hours) do
      tested = InspectionCell.where(make_key:).group(:model_key).having("SUM(tests) >= ?", min_model_tests)
        .order(Arel.sql("SUM(tests) DESC")).sum(:tests).keys
      sold = country == "US" ? ModelSale.where(make_key:).group(:model_key).order(Arel.sql("SUM(units) DESC")).sum(:units).keys : []
      (sold + tested).reject { |key| NOT_MODELS.include?(key) }.uniq.first(MAX_MODELS)
    end
  end

  def tested_makes
    InspectionCell.group(:make_key).sum(:tests)
      .each_with_object(Hash.new(0)) { |(key, tests), totals| totals[MERGED_MAKES.fetch(key, key)] += tests }
      .select { |_, tests| tests >= min_make_tests }.sort_by { |_, tests| -tests }.to_h
  end

  def us_sales_order
    ModelSale.group(:make_key).order(Arel.sql("SUM(units) DESC")).sum(:units).keys
  end
end
