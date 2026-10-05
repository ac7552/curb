module TrueCost
  # Turns a car and a buyer's plans into the four numbers, per year of ownership:
  #
  #   defect probability      P(c,t)      from DefectOdds
  #   out-of-pocket odds      P(c,t) * (1 - covered(c,t)), and 0 if a recall covers the part
  #   maintenance cost        from MaintenancePlan
  #   true cost to own        price + sum over years of (sum_c P_oop * cost_c + maintenance)
  #
  # plus break-the-bank risk: 1 - product over categories costing more than savings of (1 - P_oop).
  # That treats failures as independent, which slightly understates risk when problems cluster.
  class Calculator
    MAX_PROBLEMS = 10

    def initialize(inputs, categories: nil, terms: nil, schedule: nil, odds: nil, typical_odds: nil)
      @inputs = inputs
      @categories = categories || DefectCategory.order(:name).to_a
      @terms = terms || WarrantyTerm.for(country: inputs.market.code, make_key: inputs.make_key, model_year: inputs.model_year).to_a
      @guide = MaintenanceGuide.trusted.find_by(make_key: inputs.make_key, model_key: inputs.model_key, model_year: inputs.model_year) unless schedule
      @schedule = schedule || ServiceItem.schedule_for(make_key: inputs.make_key, model_key: inputs.model_key)
        .reject { VehicleName.electric?(make_key: inputs.make_key, engine_key: inputs.engine_key) && ServiceItem::ENGINE_ONLY.include?(_1.name) }
        .then { @guide ? @guide.apply_to(_1) : _1 }
      @odds = odds || DefectOdds.new(make_key: inputs.make_key, model_key: inputs.model_key, engine_key: inputs.engine_key,
                                     near_age: inputs.age_now)
      # An average car of the same age and mileage: no model data, so every figure is the all-car rate.
      @typical_odds = typical_odds || DefectOdds.new(make_key: "", model_key: "")
    end

    def call
      problems = @categories.reject(&:wear_item).map { |category| problem_for(category) }
      years = year_rows(problems)
      repairs_total = years.sum { |row| row[:repairs] }
      maintenance_total = years.sum { |row| row[:maintenance] }
      gross_repairs = problems.sum { |problem| problem[:expected_gross] }

      {
        currency: @inputs.market.currency,
        summary: {
          price: @inputs.price.to_f.round,
          repairs: repairs_total,
          maintenance: maintenance_total,
          running: repairs_total + maintenance_total,
          true_cost: @inputs.price.to_f.round + repairs_total + maintenance_total,
          warranty_saves: [ gross_repairs - repairs_total, 0 ].max,
          typical_repairs: typical_repairs,
          break_bank_any: break_bank_any(years),
          monthly_running: ((repairs_total + maintenance_total) / (12.0 * @inputs.years)).round
        },
        budget: budget(years),
        years:,
        problems: problems.select { |problem| problem[:chance_any] >= 0.01 }
                          .sort_by { |problem| -problem[:expected_oop] }
                          .first(MAX_PROBLEMS)
                          .map { |problem| problem.except(:expected_gross) },
        maintenance: maintenance_rows,
        schedule: schedule_rows,
        visits: visit_rows,
        schedule_source: schedule_source,
        coverage: coverage.lines.map { |line| line.to_h.merge(years_left: line.years_left.round(1)) },
        data: data_quality(problems)
      }
    end

    private
      def coverage = @coverage ||= Coverage.new(@inputs, @terms)
      def plan = @plan ||= MaintenancePlan.new(@inputs, @schedule)

      # Expected repairs for an average car of the same age, mileage and warranty, to compare against.
      def typical_repairs
        @categories.reject(&:wear_item).sum do |category|
          cost = category.repair_cost(labor_rate: @inputs.labor_rate, market: @inputs.market)
          (1..@inputs.years).sum do |t|
            p = @typical_odds.estimate(category.id, age: @inputs.age_in_year(t), band: InspectionCell.band_for(@inputs.mileage_in_year(t))).probability
            p * (1 - coverage.covered(category.warranty_type, t)) * cost
          end
        end.round
      end

      def problem_for(category)
        cost = category.repair_cost(labor_rate: @inputs.labor_rate, market: @inputs.market)
        recall = @inputs.recall_category_ids.include?(category.id)
        per_year = (1..@inputs.years).map do |t|
          estimate = @odds.estimate(category.id, age: @inputs.age_in_year(t), band: InspectionCell.band_for(@inputs.mileage_in_year(t)))
          covered = recall ? 1.0 : coverage.covered(category.warranty_type, t)
          { year: t, p: estimate.probability.round(4), p_oop: (estimate.probability * (1 - covered)).round(4),
            covered: covered.round(2), tests: estimate.tests, level: estimate.level.to_s }
        end

        {
          slug: category.slug,
          name: category.name,
          warranty_type: category.warranty_type,
          cost:,
          cost_low: (cost * 0.7).round(-1),
          cost_high: (cost * 1.4).round(-1),
          recall:,
          years: per_year,
          chance_any: chance_of_any(per_year.map { |year| year[:p] }),
          chance_any_oop: chance_of_any(per_year.map { |year| year[:p_oop] }),
          expected_oop: per_year.sum { |year| year[:p_oop] * cost }.round,
          expected_gross: per_year.sum { |year| year[:p] * cost }.round,
          confidence: DefectOdds.confidence_for(per_year.map { |year| year[:tests] }.min)
        }
      end

      def year_rows(problems)
        (1..@inputs.years).map do |t|
          repairs = problems.sum { |problem| problem[:years][t - 1][:p_oop] * problem[:cost] }.round
          maintenance = plan.cost_in_year(t)
          {
            year: t,
            age: @inputs.age_in_year(t),
            mileage: @inputs.mileage_in_year(t),
            repairs:,
            maintenance:,
            total: repairs + maintenance,
            monthly: ((repairs + maintenance) / 12.0).round,
            break_bank: break_bank(problems, t)
          }
        end
      end

      def break_bank(problems, t)
        savings = @inputs.emergency_savings
        return if savings.nil?
        big = problems.select { |problem| problem[:cost] > savings }
        chance_of_any(big.map { |problem| problem[:years][t - 1][:p_oop] })
      end

      def break_bank_any(years)
        return if @inputs.emergency_savings.nil?
        chance_of_any(years.map { |row| row[:break_bank] })
      end

      def budget(years)
        return if @inputs.monthly_budget.nil?
        worst = years.max_by { |row| row[:monthly] }
        { monthly_budget: @inputs.monthly_budget.to_f.round, worst_year: worst[:year], worst_monthly: worst[:monthly],
          fits: worst[:monthly] <= @inputs.monthly_budget.to_f }
      end

      def maintenance_rows
        plan.by_year.each_with_index.map do |services, index|
          { year: index + 1, total: services.sum(&:cost), services: services.map(&:to_h) }
        end
      end

      # Each upkeep item: how often, what it costs each time, and the guide page it comes from (none when
      # the interval is Curb's usual one).
      def schedule_rows
        pages = @guide&.pages_by_item || {}
        @schedule.map do |item|
          { name: item.name, interval_miles: item.interval_miles, interval_months: item.interval_months, wear_item: item.wear_item,
            cost: item.cost(labor_rate: @inputs.labor_rate, market: @inputs.market), guide_pages: pages[item.name],
            other_versions: @guide&.other_versions(item.name)&.map { _1.slice("interval_miles", "interval_months", "applies_to") }.presence }
        end.sort_by { |row| [ row[:guide_pages] ? 0 : 1, row[:wear_item] ? 1 : 0, row[:interval_miles] || Float::INFINITY ] }
      end

      # Upkeep as shop visits: when (months from purchase), at about what mileage, and what's done.
      def visit_rows
        pages = @guide&.pages_by_item || {}
        plan.visits.map do |visit|
          jobs = visit.items.map do |item|
            { name: item.name, cost: item.cost(labor_rate: @inputs.labor_rate, market: @inputs.market), wear_item: item.wear_item,
              guide_pages: pages[item.name] }
          end.sort_by { -_1[:cost] }
          { months: (visit.at * 12).round, miles: (@inputs.mileage + visit.at * @inputs.miles_per_year).round(-3),
            total: jobs.sum { _1[:cost] }, jobs: }
        end
      end

      # Where the upkeep intervals come from: the maker's guide for this exact car, or Curb's usual schedule (nil).
      def schedule_source
        return unless @guide
        { title: @guide.title, url: @guide.url, items: @guide.pages_by_item.slice(*@schedule.map(&:name)) }
      end

      def data_quality(problems)
        smallest = problems.flat_map { |problem| problem[:years].map { |year| year[:tests] } }.min.to_i
        {
          model_tests: @odds.model_tests,
          model_has_data: @odds.model_has_data?,
          smallest_cell: smallest,
          confidence: DefectOdds.confidence_for(smallest),
          proxy: @inputs.market.code == "US"
        }
      end

      def chance_of_any(probabilities)
        (1 - probabilities.compact.reduce(1.0) { |none, p| none * (1 - p) }).round(4)
      end
  end
end
