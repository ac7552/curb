# What US owners told NHTSA about one car. When yearly US sales are known (ModelSale), complaints are
# counted per car sold over the model year and its neighbours, and compared with the average car's rate:
# the fairest comparison, since popular cars get more complaints just by being popular. Without sales,
# three weaker comparisons stand in:
#
#   mix:         this part's share of this car's complaints vs a typical car's share, similar years
#   other years: this year's complaints about the part vs the same model's neighbouring years
#   rank:        how many car models of similar years had fewer complaints about the part
#                (popular cars get more reports, so it only counts for a part that's also over-represented)
#
# A part is flagged when it has enough complaints and stands out on any of them. Cars NHTSA files by
# trim ("C300", "328I") are added up across the trim family (see VehicleName.trim_family_pattern).
class OwnerReports
  MIN_COMPLAINTS = 25
  MIN_CAR_COMPLAINTS = 50
  MIX_FLAG = 2.0
  YEAR_FLAG = 3.0
  RANK_FLAG = 0.99
  RANK_MIN_COMPLAINTS = 100
  RANK_MIN_MIX = 1.5
  MIN_NEIGHBOUR_AVERAGE = 10
  POOL_YEARS = 2             # model years either side, added together (young cars borrow their generation's record)
  PER_CAR_FLAG = 2.0         # a part's complaints per car sold vs the average car's
  MIN_PER_CAR_COMPLAINTS = 20
  NEIGHBOUR_YEARS = 3
  MAX_BULLETIN_TITLES = 6
  # Parts where a pile of maker fixes points to an expensive problem.
  BULLETIN_PARTS = %w[engine cooling transmission hybrid-battery electrical fuel-system oil-leaks].freeze
  BULLETIN_FLAG = 0.95
  MIN_BULLETINS = 10

  Part = Data.define(:slug, :complaints, :towed, :with_miles, :miles_total)

  def self.for(make:, model:, model_year:) = new(make:, model:, model_year:).to_h

  def initialize(make:, model:, model_year:)
    @make_key = VehicleName.make_key(make)
    @model_key = VehicleName.model_key(model)
    @family = VehicleName.trim_family_pattern(make, model)
    @model_year = model_year.to_i
  end

  def to_h
    car = parts_for(@model_year)
    total = car.sum(&:complaints)
    parts = car.map { |part| describe(part, total) }
    # Parts owners of this generation complain about far more per car than owners of the average car.
    # With sales known, a part is flagged when owners report it far more often per car than for the
    # average car, or when this model year spikes against its neighbours; the weaker share and rank
    # tests only stand in when there are no sales figures.
    # A year spike only counts when the part isn't below average per car (the first year of a new
    # generation spikes against older years without being bad).
    if per_car[:overall]
      per_car[:parts].each do |slug, ratio|
        part = parts.find { |row| row[:slug] == slug } || (parts << { slug:, complaints: 0 }).last
        part[:per_car_ratio] = ratio.round(1)
        part[:pooled_complaints] = per_car[:part_complaints][slug]
      end
      parts.each do |part|
        ratio = part[:per_car_ratio].to_f
        spike = part[:year_ratio].to_f >= YEAR_FLAG && part[:complaints] >= MIN_COMPLAINTS && ratio >= 1.25
        part[:flagged] = (ratio >= PER_CAR_FLAG && part[:pooled_complaints].to_i >= MIN_COMPLAINTS) || spike
      end
    end
    parts.sort_by! { |part| -part[:complaints] }
    flagged = parts.select { |part| part[:flagged] }.map { |part| part[:slug] }
    kept = (parts.first(8) + parts.select { |part| part[:flagged] }).uniq
    { complaints: total, overall: per_car[:overall], parts: kept, flagged:, bulletins: bulletins(flagged) }
  end

  # Complaints per car sold for this model and the average car, over the pooled model years that have
  # sales figures. Empty without sales.
  def per_car
    @per_car ||= begin
      years = pool_years.select { |year| sales_by_year.key?(year) }
      if years.size < 2
        {}
      else
        units = years.sum { |year| sales_by_year[year] }
        mine = ComplaintCount.where(make_key: @make_key, model_key: sales_family.last, model_year: years)
                             .group(:category_slug).sum(:complaints)
        typical = self.class.typical_per_car(years)
        total = mine.values.sum
        # Sales but hardly any complaints means the sales page covers a differently named car
        # (a Carnival page counting the Sedona years): no per-car figure rather than a perfect one.
        return @per_car = {} if total < MIN_PER_CAR_COMPLAINTS
        overall = {
          years: [ years.min, years.max ], complaints: total, units:, family: sales_family.last.size > 1 ? sales_family.last : nil,
          per_10k: (10_000.0 * total / units).round, typical_per_10k: (10_000 * typical[:total]).round,
          ratio: typical[:total].positive? ? ((total.to_f / units) / typical[:total]).round(2) : nil
        }
        parts = mine.filter_map do |slug, count|
          rate = typical[:parts][slug].to_f
          [ slug, (count.to_f / units) / rate ] if rate.positive?
        end.to_h
        { overall:, parts:, part_complaints: mine }
      end
    end
  end

  # Complaints per car sold for the average car (all models with sales in every one of these years).
  def self.typical_per_car(years)
    (@typical_per_car ||= {})[years] ||= begin
      sold = ModelSale.where(year: years).group(:make_key, :model_key)
                      .having("COUNT(*) = ?", years.size).sum(:units)
      counts = ComplaintCount.where(model_year: years).group(:make_key, :model_key, :category_slug).sum(:complaints)
      units = sold.values.sum.to_f
      parts = Hash.new(0)
      counts.each do |(make_key, model_key, slug), n|
        parts[slug] += n if sold.key?([ make_key, ModelSale.family(make_key, model_key).first ])
      end
      units.zero? ? { total: 0.0, parts: {} } : { total: parts.values.sum / units, parts: parts.transform_values { |n| n / units } }
    end
  end

  def self.clear_cache = @typical_per_car = {}

  private
    def pool_years
      ((@model_year - POOL_YEARS)..[ @model_year + POOL_YEARS, Date.current.year ].min).to_a
    end

    def sales_family = @sales_family ||= ModelSale.family(@make_key, @model_key)

    def sales_by_year
      @sales_by_year ||= ModelSale.where(make_key: @make_key, model_key: sales_family.first).pluck(:year, :units).to_h
    end

    def this_model(scope)
      scope = scope.where(make_key: @make_key)
      @family ? scope.where("model_key ~ ?", @family) : scope.where(model_key: @model_key)
    end

    def parts_for(years)
      this_model(ComplaintCount.where(model_year: years))
        .group(:category_slug)
        .pluck(:category_slug, Arel.sql("SUM(complaints)"), Arel.sql("SUM(towed)"), Arel.sql("SUM(with_miles)"), Arel.sql("SUM(miles_total)"))
        .map { |slug, complaints, towed, with_miles, miles_total| Part.new(slug, complaints.to_i, towed.to_i, with_miles.to_i, miles_total.to_i) }
    end

    def describe(part, total)
      share = part.complaints.to_f / total
      typical = typical_shares.fetch(part.slug, 0.0)
      mix_ratio = typical.positive? ? share / typical : nil
      others = other_years.fetch(part.slug, nil)
      year_ratio = others && others >= MIN_NEIGHBOUR_AVERAGE ? part.complaints / others : nil
      rank = rank_among_cars(part)
      flagged = part.complaints >= MIN_COMPLAINTS &&
        ((mix_ratio || 0) >= MIX_FLAG || (year_ratio || 0) >= YEAR_FLAG ||
         (part.complaints >= RANK_MIN_COMPLAINTS && rank >= RANK_FLAG && (mix_ratio || 0) >= RANK_MIN_MIX))
      {
        slug: part.slug, complaints: part.complaints, share: share.round(3), typical_share: typical.round(3),
        mix_ratio: mix_ratio&.round(1), other_years_average: others&.round(1), year_ratio: year_ratio&.round(1),
        rank: rank.round(3), towed_share: (part.towed.to_f / part.complaints).round(2),
        average_miles: part.with_miles.positive? ? (part.miles_total.to_f / part.with_miles).round(-3).to_i : nil,
        flagged:
      }
    end

    # Each part's average share of a car's complaints, across car models within two model years of this
    # one. Every model counts once, so a few cars with thousands of complaints can't set what "normal" is.
    def typical_shares
      @typical_shares ||= begin
        sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, @model_year - 2, @model_year + 2, MIN_CAR_COMPLAINTS ])
          WITH cars AS (
            SELECT make_key, model_key, model_year, SUM(complaints) AS total
            FROM complaint_counts
            WHERE model_year BETWEEN ? AND ?
            GROUP BY 1, 2, 3
            HAVING SUM(complaints) >= ?
          )
          SELECT c.category_slug, SUM(c.complaints::float / cars.total) / (SELECT COUNT(*) FROM cars)
          FROM complaint_counts c
          JOIN cars USING (make_key, model_key, model_year)
          GROUP BY 1
        SQL
        rows = ActiveRecord::Base.connection.select_rows(sql)
        rows.to_h { |slug, share| [ slug, share.to_f ] }
      end
    end

    # Share of car models within two model years that had fewer complaints about this part.
    def rank_among_cars(part)
      window = ComplaintCount.where(model_year: (@model_year - 2)..(@model_year + 2))
      @car_count ||= window.distinct.count(Arel.sql("make_key || '|' || model_key || '|' || model_year"))
      return 0.0 if @car_count.zero?
      at_least = window.where(category_slug: part.slug).where("complaints >= ?", part.complaints).count
      (@car_count - at_least).to_f / @car_count
    end

    # Average yearly complaints per part for the same model's neighbouring years that have any.
    def other_years
      @other_years ||= begin
        range = ((@model_year - NEIGHBOUR_YEARS)..(@model_year + NEIGHBOUR_YEARS)).to_a - [ @model_year ]
        rows = this_model(ComplaintCount.where(model_year: range))
                 .group(:model_year, :category_slug).sum(:complaints)
                 .map { |(year, slug), complaints| [ year, slug, complaints ] }
        years = rows.map(&:first).uniq.size
        years.zero? ? {} : rows.group_by { _2 }.transform_values { |group| group.sum(&:last).to_f / years }
      end
    end

    # How many fixes the maker sent dealers, by part, and how that compares with every other car from the
    # same model year. Titles are kept for flagged parts and parts with an unusual number of fixes.
    def bulletins(flagged)
      rows = ServiceBulletin.where(make_key: @make_key, model_year: @model_year)
      rows = @family ? rows.where("model_key ~ ?", @family) : rows.where(model_key: @model_key)
      by_part = rows.where.not(category_slug: nil).group(:category_slug).distinct.count(:document_id)
      ranks = BULLETIN_PARTS.filter_map do |slug|
        count = by_part[slug].to_i
        next if count < MIN_BULLETINS
        others = ServiceBulletin.where(model_year: @model_year, category_slug: slug)
                                .group(:make_key, :model_key).distinct.count(:document_id).values
        # Share of the other cars that year (this car is in the list too) with fewer fixes for the part.
        [ slug, (others.count { |n| n < count }.to_f / (others.size - 1)).round(3) ] if others.size > 1
      end.to_h
      standout = ranks.select { |_, rank| rank >= BULLETIN_FLAG }.keys
      titles = (flagged | standout).to_h do |slug|
        [ slug, rows.where(category_slug: slug).distinct.order(:title).limit(MAX_BULLETIN_TITLES).pluck(:title) ]
      end
      { count: rows.distinct.count(:document_id), by_part:, ranks:, standout:, titles: }
    end
end
