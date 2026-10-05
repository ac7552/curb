# Normalizes make, model and engine names so that UK MOT, Dutch RDW and US vPIC spellings of the
# same car land on the same keys ("Honda", "CIVIC TYPE R" and "Civic" all become HONDA / CIVIC).
# The SQL in Importers::MotBulk applies the same rules; keep them in step.
module VehicleName
  MAKE_ALIASES = {
    "VOLKSWAGEN" => "VOLKSWAGEN", "VW" => "VOLKSWAGEN",
    "MERCEDES" => "MERCEDES-BENZ", "MERCEDES BENZ" => "MERCEDES-BENZ",
    "LANDROVER" => "LAND ROVER", "SKODA" => "SKODA", "ŠKODA" => "SKODA",
    "CITROËN" => "CITROEN"
  }.freeze

  FUEL_CODES = {
    "PE" => "P", "PETROL" => "P", "GASOLINE" => "P", "BENZINE" => "P",
    "DI" => "D", "DIESEL" => "D",
    "EL" => "E", "ELECTRIC" => "E", "ELEKTRICITEIT" => "E",
    "HY" => "H", "HYBRID" => "H", "HYBRID ELECTRIC" => "H", "HEV" => "H", "PHEV" => "H"
  }.freeze

  module_function

  def make_key(make)
    key = make.to_s.strip.upcase.squeeze(" ")
    MAKE_ALIASES.fetch(key, key)
  end

  # First words that start the name of more than one car. The second word is kept when it names a
  # different car ("TRANSIT CONNECT" isn't a "TRANSIT"); other second words are usually trims ("GOLF GTI").
  # :any keeps whatever second word follows ("MODEL 3", "GRAND CHEROKEE").
  MULTI_WORD_MODELS = {
    "MODEL" => :any, "GRAND" => :any, "LAND" => :any, "SANTA" => :any,
    "TRANSIT" => %w[CONNECT CUSTOM COURIER], "TOURNEO" => %w[CONNECT CUSTOM COURIER],
    "DISCOVERY" => %w[SPORT], "ROGUE" => %w[SPORT], "OUTLANDER" => %w[SPORT],
    "YARIS" => %w[CROSS], "COROLLA" => %w[CROSS], "MUSTANG" => %w[MACH-E], "IONIQ" => %w[5 6],
    "C3" => %w[AIRCROSS PICASSO], "C4" => %w[CACTUS PICASSO GRAND], "FOCUS" => %w[C-MAX]
  }.freeze
  RANGE_ROVERS = %w[SPORT EVOQUE VELAR].freeze

  # The model family: the first word of the model name ("GOLF GTI" -> "GOLF"), a number plus the next
  # word ("3 SERIES"), or two or three words for names shared by different cars (see MULTI_WORD_MODELS).
  # Importers call this too, so UK, Dutch and US records of the same car share one key.
  def model_key(model)
    words = model.to_s.strip.upcase.squeeze(" ").split(" ")
    first, second, third = words
    return "" if first.nil?
    return words.first(2).join(" ") if first.match?(/\A\d+\z/) && second
    return "TOWN & COUNTRY" if first == "TOWN" && %w[& AND].include?(second)
    return [ "RANGE ROVER", (third if RANGE_ROVERS.include?(third)) ].compact.join(" ") if first == "RANGE" && second == "ROVER"

    keep = MULTI_WORD_MODELS[first]
    second && (keep == :any || keep&.include?(second)) ? "#{first} #{second}" : first
  end

  # US VIN names often differ from the UK register's: "C-Class" is "C 220 ..." in MOT data, "Mazda3" is
  # "3", and every Range Rover model starts with "RANGE". Candidates to try, best first.
  def model_key_candidates(make, model)
    key = model_key(model)
    words = model.to_s.strip.upcase.squeeze(" ").split(" ")
    candidates = [ key ]
    candidates << key.delete_suffix("-CLASS") if key.end_with?("-CLASS")
    candidates << key.delete_prefix(make_key(make)) if key.start_with?(make_key(make)) && key.length > make_key(make).length
    candidates << words.first(2).join(" ") if words.size > 1
    # Trims to families: a BMW "330i" is a "3 SERIES", a Mercedes "C300" is a "C".
    if make_key(make) == "BMW" && (series = key[/\A(\d)\d{2}[A-Z]*\z/, 1])
      candidates += [ "#{series} SERIES", key[/\A\d{3}/] ]
    elsif make_key(make) == "MERCEDES-BENZ" && (letters = key[/\A([A-Z]{1,3})\d{2,3}[A-Z]*\z/, 1])
      candidates += [ letters, "#{letters}-CLASS" ]
    end
    candidates.compact_blank.uniq
  end

  # NHTSA files many cars by trim ("C300", "CLA250", "328I"). A regex for every trim in the same family,
  # or nil when the model name is used as-is.
  def trim_family_pattern(make, model)
    make = make_key(make)
    key = model_key(model)
    case make
    when "MERCEDES-BENZ"
      letters = key[/\A([A-Z]{1,3})(-CLASS|\d{2,3}[A-Z]*)?\z/, 1]
      "^#{letters}(-CLASS|\\d{2,3}[A-Z]*)?$" if letters
    when "BMW"
      series = key[/\A(\d) SERIES\z/, 1] || key[/\A(\d)\d{2}[A-Z]*\z/, 1]
      "^(#{series} SERIES|#{series}\\d{2}[A-Z]*)$" if series
    end
  end

  # Makers that only build electric cars, for when a check doesn't say the fuel.
  ELECTRIC_MAKES = %w[TESLA RIVIAN LUCID POLESTAR].freeze

  def electric?(make_key:, engine_key:) = engine_key == "EV" || ELECTRIC_MAKES.include?(make_key)

  # "1.5-P": displacement in liters to one decimal, then a fuel letter. Electric cars are "EV".
  def engine_key(cc: nil, liters: nil, fuel: nil)
    fuel_code = fuel_code(fuel)
    return "EV" if fuel_code == "E"
    liters ||= cc.to_f / 1000 if cc.to_i.positive?
    return nil if liters.to_f <= 0
    [ format("%.1f", liters.to_f.round(1)), fuel_code ].compact.join("-")
  end

  def fuel_code(fuel)
    text = fuel.to_s.strip.upcase
    return if text.empty?
    FUEL_CODES[text] || FUEL_CODES.find { |name, _| text.include?(name) && name.length > 2 }&.last
  end

  # Makes written as letters stay in capitals ("BMW", not "Bmw").
  UPPERCASE_MAKES = %w[BMW GMC MG DS VW MINI RAM].freeze

  def display_make(make)
    key = make.to_s.strip.upcase
    UPPERCASE_MAKES.include?(key) ? key : make.to_s.strip.titleize
  end

  # All-caps register names read better as "Civic", but "CR-V", "RAV4" and "GTI" stay as they are.
  def display_model(model)
    text = model.to_s.strip
    return text unless text == text.upcase
    text.split(" ").map { |word| word.match?(/\A[A-Z]{4,}\z/) ? word.capitalize : word }.join(" ")
  end

  def display(make:, model:) = [ display_make(make), display_model(model) ].join(" ")
end
