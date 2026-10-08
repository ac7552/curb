module ReportsHelper
  COUNTRY_LABELS = { "US" => "United States", "GB" => "United Kingdom", "NL" => "Netherlands" }.freeze

  INSURANCE_COVERAGES = {
    bodily_injury: "Injuries you cause", property_damage: "Damage you cause", pip: "Your own injuries",
    uninsured: "Drivers with no insurance", collision: "Your car, in a crash", comprehensive: "Your car: theft, weather, fire"
  }.freeze

  def insurance_coverage_name(coverage) = INSURANCE_COVERAGES.fetch(coverage) { coverage.to_s.humanize }

  # Plain names for each kind of warranty, with the dealer's word for it.
  COVERAGE_NAMES = {
    "bumper_to_bumper" => [ "Most parts", "bumper-to-bumper" ],
    "powertrain" => [ "Engine and transmission", "powertrain" ],
    "corrosion" => [ "Rust holes in the body", "corrosion" ],
    "emissions" => [ "Exhaust cleanup parts", "emissions" ]
  }.freeze

  CONFIDENCE_WORDS = { "high" => "Strong guess", "medium" => "Fair guess", "low" => "Rough guess" }.freeze

  # Where each kind of finding comes from. :nhtsa_vehicle links to NHTSA's page for the exact car, where
  # its complaints, recalls and maker bulletins can be read. Prices, schedules and warranty terms are
  # Curb's own starter tables (db/seeds), and say so.
  SOURCES = {
    mot: [ "UK MOT test records (DVSA)", "https://www.data.gov.uk/dataset/c63fca52-ae4c-4b75-bab5-8b4735e1a4c9/anonymised-mot-tests-and-results" ],
    complaints: [ "Owner complaints to NHTSA", :nhtsa_vehicle ],
    bulletins: [ "Maker bulletins filed with NHTSA", :nhtsa_vehicle ],
    recalls: [ "NHTSA recalls", :nhtsa_vehicle ],
    sales: [ "US sales figures from Wikipedia (CC BY-SA)", "https://en.wikipedia.org/" ],
    mot_history: [ "GOV.UK MOT history", "https://www.check-mot.service.gov.uk/" ],
    rdw: [ "RDW, the Dutch vehicle register", "https://ovi.rdw.nl/" ],
    warranty: [ "Maker warranty terms (Curb's table, confirm with the seller)", nil ],
    estimates: [ "Curb's repair and upkeep price estimates", nil ]
  }.freeze
  NHTSA_DATA_URL = "https://www.nhtsa.gov/nhtsa-datasets-and-apis".freeze

  def nhtsa_vehicle_url(report)
    return NHTSA_DATA_URL unless report
    path = [ report.model_year, report.make.to_s.upcase, report.model.to_s.upcase ].map { |part| ERB::Util.url_encode(part.to_s) }
    "https://www.nhtsa.gov/vehicle/#{path.join("/")}"
  end

  # The SOURCES key for one piece of weak-spot evidence (see ModelProfile).
  def evidence_source(item) = { "uk" => :mot, "owners" => :complaints, "bulletins" => :bulletins }.fetch(item[:source], :mot)

  def nhtsa_recall_url(campaign) = "https://www.nhtsa.gov/recalls?nhtsaId=#{ERB::Util.url_encode(campaign.to_s)}"

  def source_url(key, report = nil)
    url = SOURCES.fetch(key).last
    url == :nhtsa_vehicle ? nhtsa_vehicle_url(report) : url
  end

  FEW_INSPECTIONS = 200
  FEW_COMPLAINTS = 50

  # A finding's citation with how many records it rests on: "Owner complaints to NHTSA (275 reports)",
  # plus a plain warning when that's only a few.
  def cite_with_count(key, report)
    count, few = case key
    when :mot
      tests = report.result.dig(:data, :model_tests).to_i
      [ ("#{number_with_delimiter(tests)} inspections" if tests.positive?), tests < FEW_INSPECTIONS ]
    when :complaints
      complaints = report.live.dig(:owner_reports, :complaints).to_i
      [ ("#{number_with_delimiter(complaints)} reports" if complaints.positive?), complaints < FEW_COMPLAINTS ]
    end
    label = [ SOURCES.fetch(key).first, ("(#{count})" if count) ].compact.join(" ")
    warning = tag.span("Only a few records, so treat this as a rough guess.", class: "cite cite--warn") if few
    safe_join([ cite(key, report, label:), warning ].compact)
  end

  SHORT_JOB_NAMES = {
    "Oil and filter change" => "Oil change", "Tires (set of four)" => "New tires", "Front brake pads and discs" => "Front brakes",
    "Rear brake pads" => "Rear brakes", "Brake fluid change" => "Brake fluid", "Coolant change" => "Coolant", "Wiper blades" => "Wipers"
  }.freeze

  # The short name a visit's list uses ("Oil change" for "Oil and filter change").
  def short_job_name(name) = SHORT_JOB_NAMES.fetch(name, name)

  # "Every 10,000 mi or 12 months", whichever comes first.
  def service_interval(row, market)
    parts = [ (distance(row[:interval_miles], market) if row[:interval_miles]), (months_or_years(row[:interval_months]) if row[:interval_months]) ]
    "Every #{parts.compact.join(" or ")}"
  end

  def months_or_years(months) = months >= 24 && (months % 12).zero? ? pluralize(months / 12, "year") : pluralize(months, "month")

  # Where an upkeep item's timing comes from, and any other timing the guide gives for other engines.
  def service_source(row, report, market)
    return row[:wear_item] ? "Replace when worn (our estimate)" : "Typical car (our estimate)" unless row[:guide_pages]
    source = "#{report.make} guide, page #{row[:guide_pages].join(", ")}"
    others = Array(row[:other_versions]).map do |other|
      "#{service_interval(other.symbolize_keys, market).downcase_first}#{" for #{other[:applies_to].to_s.delete_suffix(" only")}" if other[:applies_to].present?}"
    end
    others.any? ? "#{source}. Some engines: #{others.to_sentence}" : source
  end

  # Rounded parts that still add up to the total: each to the nearest step, with the rounding
  # difference put on the biggest part, so a column of yearly amounts matches the figure above it.
  def split_to_total(parts, total, step: 10)
    rounded = parts.map { |part| (part.to_f / step).round * step }
    rounded[rounded.index(rounded.max)] += total - rounded.sum if rounded.any?
    rounded
  end

  # "Source: Owner complaints to NHTSA ↗", linked when the source is public.
  def cite(key, report = nil, label: nil)
    name = label || SOURCES.fetch(key).first
    if (url = source_url(key, report))
      link_to("Source: #{name} ↗", url, class: "cite", target: "_blank", rel: "noopener")
    else
      tag.span("Source: #{name}", class: "cite")
    end
  end

  # Settings the new-check form needs in the browser.
  def report_form_markets
    Market::ALL.transform_values do |market|
      { symbol: market.symbol, unit: market.distance_unit, lookup: market.lookup,
        plate_example: { "GB" => "e.g. AB12 CDE", "NL" => "e.g. 12-ABC-3" }[market.code],
        yearly: Market.from_miles(market.default_miles_per_year, market.code),
        regions: LaborRate.regions_for(market.code) }
    end
  end

  # Each market's makes for the new-check form's logo grid.
  def report_form_makes
    Market.codes.index_with { |code| MakeCatalog.makes(code) }
  end

  # Where the new-check form opens: the first question still unanswered, or the one an error is about.
  def report_form_start_step(report)
    errors = report.errors
    if errors[:make].any? || report.make.blank? then 0
    elsif errors[:model_year].any? || report.model_year.blank? then 1
    elsif errors[:model].any? || errors[:base].any? || report.model.blank? then 2
    else 3
    end
  end

  # The make's badge, or its initials when we have no badge for it. If the badge fails to load,
  # application.js swaps in the initials.
  def make_logo(make)
    initials = make.to_s.scan(/\b[[:alnum:]]/).first(2).join.upcase
    if (url = MakeCatalog.logo_url(make))
      image_tag(url, alt: "", class: "make-logo", loading: "lazy", draggable: false, data: { initials: })
    else
      tag.span(initials, class: "make-logo make-logo--mono", aria: { hidden: true })
    end
  end

  def catalog_options
    @catalog_options ||= InspectionCell.catalog.keys.map do |make_key, model_key|
      [ VehicleName.display_make(make_key), VehicleName.display_model(model_key) ]
    end
  end

  # The part's current plain name and what it does, so older checks pick up wording changes too.
  def part_name_and_blurb(problem)
    @parts ||= DefectCategory.pluck(:slug, :name, :blurb).to_h { |slug, name, blurb| [ slug, [ name, blurb ] ] }
    @parts.fetch(problem[:slug], [ problem[:name], nil ])
  end

  # Round money the way people say it: $19,317 -> $19,300, $234 -> $230, $92 -> $90.
  def about_money(amount, market) = money(about_amount(amount), market)

  # The bill's total: the price plus the upkeep and repairs lines as they're shown, so the bill adds up.
  def bill_total(summary) = summary[:price].to_f + about_amount(summary[:maintenance]) + about_amount(summary[:repairs])

  def about_amount(amount)
    amount = amount.to_f
    step = if amount >= 1_000 then 100 elsif amount >= 100 then 10 else 5 end
    (amount / step).round * step
  end

  # How many out of 10 cars like this one; nil when it's fewer than 1 in 10.
  def out_of_ten(probability)
    probability.to_f >= 0.1 ? (probability * 10).round : nil
  end

  # "3 out of 10 cars like this", "about 1 out of 20 cars like this", "almost no cars like this".
  def cars_like_this(probability)
    if (count = out_of_ten(probability)) then "#{count} out of 10 cars like this"
    elsif probability.to_f >= 0.01
      n = (1 / probability).round
      n = n > 20 ? (n / 10.0).round * 10 : n
      "about 1 out of #{n} cars like this"
    else "almost no cars like this"
    end
  end

  # Boxes to draw and how many to fill: 10 boxes for 1-in-10 or more, 20 boxes with one filled for
  # about 1 in 20, and no picture for rarer chances (a row of empty boxes says nothing).
  def chance_picture(probability)
    if (count = out_of_ten(probability)) then [ 10, count ]
    elsif probability.to_f >= 0.045 then [ 20, 1 ]
    end
  end

  def likelihood_word(probability)
    if probability >= 0.3 then "Likely"
    elsif probability >= 0.1 then "Could happen"
    else "Not likely"
    end
  end

  # "1 out of 3", "1 out of 12": a whole-number way to say a share.
  def out_of(share)
    return "almost none" if share.to_f < 0.01
    return "#{(share * 10).round} out of 10" if share >= 0.5
    "1 out of #{(1 / share).round}"
  end

  # "about 1 in 9" reads more easily than "11%".
  def one_in(probability)
    return "almost no" if probability.to_f < 0.01
    return "about #{(probability * 10).round} in 10" if probability >= 0.5
    "about 1 in #{(1 / probability).round}"
  end

  def distance_word(market) = market.distance_unit == "km" ? "kilometers" : "miles"

  def break_bank_status(chance)
    if chance < 0.10 then :good
    elsif chance < 0.25 then :warning
    else :critical
    end
  end

  def risk_words(kind)
    { good: "Low risk", warning: "Some risk", critical: "High risk" }.fetch(kind)
  end

  def confidence_tag(level)
    dot = { "high" => "dot-green", "medium" => "dot-blue", "low" => "dot-orange" }.fetch(level, "dot-orange")
    tag.span(class: "tag", title: "How sure we are, based on how many cars like this we have records for") do
      tag.span(class: "dot", style: "--dot: var(--#{dot})") + CONFIDENCE_WORDS.fetch(level, "Rough guess")
    end
  end

  def coverage_summary(problem)
    return "Has a free recall fix" if problem[:recall]
    return "Warranty never covers this" if problem[:warranty_type] == "none"

    covered = problem[:years].map { |year| year[:covered] }
    if covered.all?(&:zero?) then "Warranty has ended"
    elsif covered.all? { |share| share >= 1 } then "Warranty covers this"
    else "Warranty covers it for a while"
    end
  end

  def years_left_text(years)
    return "Ended" if years <= 0
    return "Less than a year left" if years < 1
    "About #{number_with_precision(years, precision: 1, strip_insignificant_zeros: true)} more years"
  end

  # "STEERING:LINKAGES:TIE ROD ASSEMBLY" -> "Steering: tie rod assembly"
  def recall_part(component)
    parts = component.to_s.split(":").map(&:strip).compact_blank
    return "Recall" if parts.empty?
    [ parts.first.capitalize, (parts.last.downcase if parts.size > 1) ].compact.join(": ")
  end

  BIG_BILL_PARTS = %w[engine transmission hybrid-battery].freeze
  OWNER_THINK_TWICE = 1.75   # problems per car sold vs the average car
  # Makes whose parts and dealer labor cost far more than the typical car our prices are based on.
  COSTLY_MAKES = %w[MASERATI FERRARI LAMBORGHINI BENTLEY ROLLS-ROYCE ASTON\ MARTIN MCLAREN LOTUS PORSCHE
                    LAND\ ROVER JAGUAR ALFA\ ROMEO TESLA].freeze
  ENOUGH_TESTS = 100

  # Our overall take and the short reasons behind it, in the order a buyer should read them.
  def report_verdict(report)
    r = report.result
    market = report.market
    summary = r[:summary]
    owners = report.live[:owner_reports] || {}
    flagged = Array(owners[:flagged]).first(2)
    reasons = []

    # Enough inspections of this model at the ages it will be while you own it to compare it fairly.
    enough_data = r[:data][:model_has_data] && r[:data][:smallest_cell].to_i >= ENOUGH_TESTS
    costly = COSTLY_MAKES.include?(report.make_key)
    typical = summary[:typical_repairs].to_f
    ratio = typical.positive? && enough_data ? summary[:repairs] / typical : nil

    # At most three reasons, most important first: a short headline, what it means for the buyer's
    # money, and where it comes from (a SOURCES key). Written for someone reading on a phone on the lot, so short words and one idea each.
    model_name = VehicleName.display(make: report.make, model: report.model)
    overall = owners[:overall]
    owner_ratio = overall && overall[:ratio]
    reasons << [ :critical, "#{VehicleName.display_make(report.make)} repairs cost a lot", "Parts and labor cost more than on most cars, so our numbers may be too low.", :estimates ] if costly

    owner_line = if owner_ratio.nil? then nil
    elsif owner_ratio >= OWNER_THINK_TWICE then [ :critical, "Owners report lots of problems", "#{how_many(owner_ratio).upcase_first} as most cars. Expect more trips to the shop.", :complaints ]
    elsif owner_ratio >= 1.3 then [ :warning, "Owners report more problems than usual", "Expect a few more trips to the shop than with most cars.", :complaints ]
    elsif owner_ratio <= 0.7 then [ :good, "Owners report few problems", "Fewer than most cars. That usually means fewer surprise bills.", :complaints ]
    else [ :info, "Owners report a normal number of problems", "About the same as most cars.", :complaints ]
    end
    # Inspections only see safety items, so for costly makes they say little about the big bills.
    uk_line = if ratio.nil? || costly then nil
    elsif ratio <= 0.8 then [ :good, "Breaks less than most cars its age", "Small parts like brakes and lights wear out less often. That means fewer repair bills.", :mot ]
    elsif ratio <= 1.25 then [ :info, "Breaks about as often as most cars its age", "Expect the usual small fixes, like brakes and lights.", :mot ]
    else [ :warning, "Breaks more than most cars its age", "Small parts like brakes and lights wear out more often. Plan for more repair bills.", :mot ]
    end
    reasons << (owner_line || uk_line) if owner_line || uk_line

    if flagged.any?
      # "Battery and wiring" -> "the battery", so a list of two parts reads clearly.
      names = flagged.map { |slug| "the #{part_name_and_blurb({ slug: }).first.downcase.split(" and ").first}" }
      reasons << [ :warning, "Watch out for #{names.join(" and ")}", "These break more often on this car. Have a mechanic check them before you buy.", :complaints ]
    end

    # Only the warranties that pay for real repairs count here; rust-through cover rarely matters. Each
    # line says how we know: the maker's terms against this car's age and miles.
    main = r[:coverage].index_by { |line| line[:coverage_type] }
    left = ->(type) { main.dig(type, :years_left).to_f }
    maker = VehicleName.display_make(report.make)
    reasons << if r[:coverage].all? { |line| line[:source] == "none" }
      [ :info, "Ask about the warranty", "We don't have #{maker}'s warranty on file. Ask the seller how many years and miles are left.", :warranty ]
    elsif left.("bumper_to_bumper") >= 1
      [ :good, "Warranty covers most repairs for #{pluralize(left.("bumper_to_bumper").round, "more year")}",
        "#{maker}'s warranty lasts #{warranty_term_text(report, "bumper_to_bumper")}. If something breaks before then, the maker pays.", :warranty ]
    elsif left.("powertrain") >= 1
      [ :good, "Warranty covers the engine for #{pluralize(left.("powertrain").round, "more year")}",
        "#{maker} covers the engine and transmission for #{warranty_term_text(report, "powertrain")}. You pay for other repairs.", :warranty ]
    elsif main.dig("powertrain", :note).present?
      [ :info, "No warranty left", "#{maker}'s warranty doesn't pass to a second owner. You pay for every repair.", :warranty ]
    else
      age = r[:years].first&.dig(:age)
      car = [ ("#{age} years old" if age), "has #{distance(report.current_mileage, market)}" ].compact.join(" and ")
      [ :info, "No warranty left", "#{maker}'s warranty lasts up to #{warranty_term_text(report, "powertrain") || "a few years"}. This car is #{car}, so it has run out. You pay for every repair.", :warranty ]
    end

    reasons << uk_line if owner_line && uk_line
    # Recalls are something to do, not a judgement of the car, so they sit on the "Before you buy" list.
    reasons = reasons.first(3)
    standout = Array(owners.dig(:bulletins, :standout))

    verdict = if costly
      { kind: :critical, label: "Costly to fix", text: "#{VehicleName.display_make(report.make)}s usually cost a lot to repair, and our data can't see their biggest repairs. Get a mechanic's check and a repair quote before you buy." }
    elsif (owner_ratio && owner_ratio >= OWNER_THINK_TWICE) || (!enough_data && flagged.intersect?(BIG_BILL_PARTS))
      { kind: :critical, label: "Think twice", text: "Owners of this car report a lot more problems than owners of most cars. Read why below before you buy." }
    elsif !enough_data && owner_ratio.nil?
      { kind: costly ? :critical : :info, label: "Not enough data",
        text: costly ? "We can't judge this car well, and cars like it usually cost a lot to fix. Get a mechanic's check before you buy." : "We don't have enough records to judge this car well. Get a mechanic's check before you buy." }
    elsif (ratio && ratio > 1.5) || flagged.intersect?(BIG_BILL_PARTS) || standout.intersect?(BIG_BILL_PARTS)
      { kind: :critical, label: "Think twice", text: "This car has a higher risk of big repair bills. Read why below before you buy." }
    elsif (ratio.nil? || ratio <= 0.9) && (owner_ratio.nil? ? ratio : owner_ratio <= 1) && flagged.empty? && standout.empty? && !costly
      { kind: :good, label: "Good pick", text: "This car should have fewer money surprises than most cars like it." }
    else
      { kind: :warning, label: "OK pick", text: "This car's costs are about normal. Check the notes below." }
    end
    verdict.merge(reasons:, costly:)
  end

  # "5 years or 60,000 mi": how long one kind of the maker's warranty lasts, whichever comes first.
  def warranty_term_text(report, coverage_type)
    term = WarrantyTerm.for(country: report.country, make_key: report.make_key, model_year: report.model_year).find_by(coverage_type:)
    return unless term
    [ pluralize(term.years, "year"), (distance(term.miles, report.market) if term.miles) ].compact.join(" or ")
  end

  # Whole numbers only: "2 times as often as", "more than 4 times as often as", or "more often than".
  def how_often(ratio)
    ratio = ratio.to_f
    if ratio < 1.75 then "more often than"
    elsif ratio >= 4.5 then "more than 4 times as often as"
    else "#{ratio.round} times as often as"
    end
  end

  # "twice as many", "3 times as many", "more than 4 times as many"
  def how_many(ratio)
    ratio = ratio.to_f
    if ratio < 2.5 then "about twice as many"
    elsif ratio >= 4.5 then "more than 4 times as many"
    else "about #{ratio.round} times as many"
    end
  end

  # What fixing a weak spot usually costs: this car's own repair estimate when we have one, or the
  # typical bill for the part.
  def weak_spot_cost(report, slug)
    problem = report.result[:problems].find { |row| row[:slug] == slug }
    return problem[:cost] if problem
    DefectCategory.find_by(slug:)&.repair_cost(labor_rate: report.labor_rate.to_f, market: report.market)
  end

  # "Common problem" when two kinds of records agree, or one shows it far more often than usual.
  def weak_spot_label(spot)
    spot[:sources] > 1 || spot[:evidence].any? { |item| item[:score] >= 3 } ? "Common problem" : "Some signs"
  end

  # One short sentence for a piece of weak-spot evidence (see ModelProfile).
  def weak_spot_sentence(item, _part, make)
    case item[:source]
    when "uk"
      "UK safety checks find it #{how_often(item[:ratio])} on other cars this age."
    when "owners"
      if item[:per_car_ratio].to_f >= OwnerReports::PER_CAR_FLAG
        "US owners report it #{how_often(item[:per_car_ratio])} owners of most cars."
      elsif item[:mix_ratio].to_f >= OwnerReports::MIX_FLAG
        "US owners report it #{how_often(item[:mix_ratio])} owners of most cars."
      elsif item[:year_ratio].to_f >= OwnerReports::YEAR_FLAG
        "Owners of this year report it #{how_often(item[:year_ratio])} owners of other years."
      else
        "US owners report it more than owners of 99 out of 100 other cars."
      end
    when "bulletins"
      maker = VehicleName.display_make(make)
      fixes = pluralize(item[:count], "fix", plural: "fixes")
      if item[:theme]
        "#{maker} sent dealers #{fixes} for #{BulletinTheme.find(item[:theme]).label}. Most cars get far fewer."
      else
        out_of_100 = [ (item[:rank].to_f * 100).floor, 99 ].min
        "#{maker} sent dealers #{fixes}. That's more than #{out_of_100} out of 100 other cars."
      end
    end
  end
end
