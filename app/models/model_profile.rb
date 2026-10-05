# A model's known weak spots, pieced together from three independent kinds of evidence:
#
#   uk:        how often UK safety inspections record each part on this model (fail or advisory),
#              compared with an average car of the same age (ModelPartProfile)
#   owners:    parts US owners complain about far more than usual (OwnerReports)
#   bulletins: parts and known failure themes the maker sent dealers an unusual number of fixes for,
#              compared with every other model from the same years (ServiceBulletin, BulletinTheme)
#
# Evidence is grouped by part, and a part backed by more sources ranks higher. Nothing here is a
# probability: it says where a model tends to have trouble, not how likely a given car is to have it.
class ModelProfile
  YEARS_AROUND = 1           # build years either side of the car's model year (wider mixes in older generations)
  MIN_TESTS = 1_000          # UK inspections needed before a model gets a UK profile
  MIN_HITS = 30              # UK inspections that recorded a part before it can be flagged
  RATIO_PRIOR = 20           # acts like 20 expected cases at the average rate, so thin parts stay near 1x
  UK_FLAG = 1.3
  UK_STRONG = 2.0
  UK_BETTER = 0.7
  THEME_MIN_FIXES = 4
  THEME_FLAG = 2.5           # the theme's share of this car's fixes vs its share of all cars' fixes
  THEME_STRONG = 5.0
  SKIPPED_PARTS = %w[tyres brake-wear wipers other plates-id horn].freeze   # wear items, paperwork, trivial
  # Parts UK inspections actually look at, so "holds up well" means something for them.
  INSPECTED_PARTS = %w[suspension shock-absorbers springs steering wheel-bearings brake-hydraulics parking-brake abs
                       lights exhaust body-corrosion body drive-shafts restraints glass-mirrors fuel-system].freeze

  def self.for(**) = new(**).to_h

  def self.theme_shares_cache = @theme_shares_cache ||= {}
  def self.clear_cache = @theme_shares_cache = {}

  def initialize(make:, model:, model_year:, engine_key: nil)
    @make = make
    @model = model
    @make_key = VehicleName.make_key(make)
    @model_year = model_year.to_i
    @engine_key = engine_key.presence
    @build_years = (@model_year - YEARS_AROUND)..(@model_year + YEARS_AROUND)
  end

  def to_h
    evidence = uk_evidence + owner_evidence + bulletin_evidence
    spots = evidence.group_by { |item| item[:slug] }.map do |slug, items|
      # Each kind of record counts once per part, at its strongest, so five bulletin themes about the
      # engine don't outweigh one finding from tens of thousands of inspections.
      score = items.group_by { |item| item[:source] }.sum { |_, same| same.map { |item| item[:score] }.max }
      { slug:, sources: items.map { |item| item[:source] }.uniq.size, score:,
        evidence: items.sort_by { |item| %w[uk owners bulletins].index(item[:source]) } }
    end
    {
      make: @make, model: @model, model_year: @model_year, build_years: [ @build_years.first, @build_years.last ],
      uk: uk_summary, weak_spots: spots.sort_by { |spot| [ -spot[:sources], -spot[:score] ] }, better: better_parts
    }
  end

  private
    # ---- UK inspections ----

    def uk_rows
      @uk_rows ||= begin
        key = uk_model_key
        engine = @engine_key && uk_tests(key, @engine_key) >= MIN_TESTS ? @engine_key : "*"
        @uk_engine = engine
        ModelPartProfile.where(make_key: @make_key, model_key: key, engine_key: engine, build_year: @build_years)
          .group(:defect_category_id)
          .pluck(:defect_category_id, Arel.sql("SUM(hits)"), Arel.sql("SUM(expected_hits)"))
          .to_h { |id, hits, expected| [ id, [ hits.to_i, expected.to_f ] ] }
      end
    end

    # The spelling of the model with the most UK data ("C-Class" is "C" in UK records).
    def uk_model_key
      @uk_model_key ||= VehicleName.model_key_candidates(@make, @model).max_by { |key| uk_tests(key, "*") }
    end

    # Inspections of a model and engine over the build years (each group's total, counted once).
    def uk_tests(model_key, engine_key)
      ModelPartProfile.where(make_key: @make_key, model_key:, engine_key:, build_year: @build_years)
        .distinct.pluck(:build_year, :tests).sum(&:last)
    end

    def uk_summary
      uk_rows
      { model_key: uk_model_key, engine_key: @uk_engine, tests: uk_tests(uk_model_key, @uk_engine) }
    end

    def uk_ratios
      return {} if uk_summary[:tests] < MIN_TESTS
      categories = DefectCategory.where(id: uk_rows.keys).where.not(slug: SKIPPED_PARTS).pluck(:id, :slug).to_h
      uk_rows.filter_map do |id, (hits, expected)|
        next unless categories[id]
        [ categories[id], hits, (hits + RATIO_PRIOR) / (expected + RATIO_PRIOR) ]
      end
    end

    def uk_evidence
      @uk_evidence ||= uk_ratios.filter_map do |slug, hits, ratio|
        next unless hits >= MIN_HITS && ratio >= UK_FLAG
        # Thousands of inspections behind every UK figure, so it weighs more than a handful of bulletins.
        { slug:, source: "uk", ratio: ratio.round(2), count: hits, score: ratio >= UK_STRONG ? 3 : (ratio >= 1.5 ? 2 : 1) }
      end
    end

    def better_parts
      weak = to_weak_slugs
      uk_ratios.filter_map do |slug, _, ratio|
        { slug:, ratio: ratio.round(2) } if ratio <= UK_BETTER && INSPECTED_PARTS.include?(slug) && !weak.include?(slug)
      end.sort_by { |part| part[:ratio] }
    end

    def to_weak_slugs = @weak_slugs ||= (uk_evidence + owner_evidence + bulletin_evidence).map { |item| item[:slug] }.uniq

    # ---- US owner complaints and maker fixes by part ----

    def owner_reports
      @owner_reports ||= OwnerReports.for(make: @make, model: @model, model_year: @model_year)
    end

    def owner_evidence
      @owner_evidence ||= owner_reports[:parts].select { |part| part[:flagged] }.map do |part|
        strong = part[:per_car_ratio].to_f >= 3 || part[:mix_ratio].to_f >= 3 || part[:year_ratio].to_f >= 4 || part[:rank].to_f >= 0.99
        { slug: part[:slug], source: "owners", count: part[:complaints], mix_ratio: part[:mix_ratio], per_car_ratio: part[:per_car_ratio],
          year_ratio: part[:year_ratio], rank: part[:rank], score: strong ? 3 : 2 }
      end
    end

    def bulletin_evidence
      @bulletin_evidence ||= begin
        counts = theme_counts
        total = this_model_bulletins.distinct.count(:document_id)
        themes = counts.filter_map do |slug, fixes|
          theme = BulletinTheme.find(slug)
          next unless theme && fixes >= THEME_MIN_FIXES && BulletinTheme.applies?(slug, @engine_key)
          typical = typical_theme_shares[slug].to_f
          next if total.zero? || typical.zero?
          mix = (fixes.to_f / total) / typical
          next if mix < THEME_FLAG
          { slug: theme.category, source: "bulletins", theme: slug, count: fixes, mix_ratio: mix.round(1),
            score: mix >= THEME_STRONG && fixes >= 10 ? 2 : 1 }
        end
        covered = themes.map { |item| item[:slug] }
        parts = Array(owner_reports.dig(:bulletins, :standout)).reject { |slug| covered.include?(slug) }.map do |slug|
          { slug:, source: "bulletins", count: owner_reports.dig(:bulletins, :by_part, slug).to_i,
            rank: owner_reports.dig(:bulletins, :ranks, slug), score: 1 }
        end
        themes + parts
      end
    end

    def bulletin_years = (@model_year - 1)..(@model_year + 1)

    def this_model_bulletins
      rows = ServiceBulletin.where(make_key: @make_key, model_year: bulletin_years)
      family = VehicleName.trim_family_pattern(@make, @model)
      family ? rows.where("model_key ~ ?", family) : rows.where(model_key: VehicleName.model_key(@model))
    end

    # Distinct fixes per theme for this model over the bulletin years.
    def theme_counts
      this_model_bulletins.where("cardinality(themes) > 0")
        .group(Arel.sql("unnest(themes)")).distinct.count(:document_id)
    end

    # Each theme's share of all fixes makers sent for cars from the same years. The same for every
    # model, so it's kept per year range until bulletins are reloaded (see .clear_cache).
    def typical_theme_shares
      self.class.theme_shares_cache[bulletin_years] ||= begin
        window = ServiceBulletin.where(model_year: bulletin_years)
        all = window.distinct.count(:document_id).to_f
        counts = window.where("cardinality(themes) > 0").group(Arel.sql("unnest(themes)")).distinct.count(:document_id)
        all.zero? ? {} : counts.transform_values { |n| n / all }
      end
    end
end
