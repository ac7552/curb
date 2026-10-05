module TrueCost
  # Which routine services fall in each year of ownership. Each item is due every interval_miles or
  # interval_months, whichever comes first, and is assumed to be up to date on the day of purchase.
  class MaintenancePlan
    Service = Data.define(:name, :count, :unit_cost, :cost, :wear_item)

    def initialize(inputs, items)
      @inputs = inputs
      @items = items
    end

    # [[Service, ...] for year 1, [...] for year 2, ...]
    def by_year
      @by_year ||= (1..@inputs.years).map do |t|
        @items.filter_map do |item|
          count = due_times(item).count { |time| time > t - 1 && time <= t }
          next if count.zero?
          unit_cost = item.cost(labor_rate: @inputs.labor_rate, market: @inputs.market)
          Service.new(name: item.name, count:, unit_cost:, cost: unit_cost * count, wear_item: item.wear_item)
        end
      end
    end

    def cost_in_year(t) = by_year[t - 1].sum(&:cost)

    Visit = Data.define(:at, :items) # at: years from purchase

    # The same services as trips to a shop. The most frequent routine job (usually the oil change) sets
    # the visits, and anything due within VISIT_WINDOW of one is done then; anything further away is a
    # visit of its own, shared with others due close to it.
    VISIT_WINDOW = 0.5

    def visits
      events = @items.flat_map { |item| due_times(item).map { |time| [ time, item ] } }.sort_by(&:first)
      return [] if events.empty?

      pacer = events.group_by(&:last).max_by { |item, due| [ item.wear_item ? 0 : 1, due.size ] }.first
      visits = events.select { |_, item| item == pacer }.map { |time, _| Visit.new(at: time, items: []) }
      events.each do |time, item|
        visit = visits.min_by { |candidate| (candidate.at - time).abs }
        unless (visit.at - time).abs <= VISIT_WINDOW
          visit = Visit.new(at: time, items: [])
          visits << visit
        end
        visit.items << item
      end
      visits.sort_by(&:at)
    end

    private
      # Years from purchase at which the item is due.
      def due_times(item)
        spacing = [ miles_spacing(item), months_spacing(item) ].compact.min
        return [] unless spacing&.positive?
        first = [ miles_until_due(item), months_until_due(item) ].compact.min
        (0..).lazy.map { |k| first + k * spacing }.take_while { |time| time <= @inputs.years }.to_a
      end

      def miles_spacing(item)
        item.interval_miles.to_f / @inputs.miles_per_year if item.interval_miles.to_i.positive?
      end

      def months_spacing(item)
        item.interval_months / 12.0 if item.interval_months.to_i.positive?
      end

      def miles_until_due(item)
        return unless item.interval_miles.to_i.positive?
        (item.interval_miles - @inputs.mileage % item.interval_miles).to_f / @inputs.miles_per_year
      end

      def months_until_due(item)
        return unless item.interval_months.to_i.positive?
        age_months = @inputs.age_now * 12
        (item.interval_months - age_months % item.interval_months) / 12.0
      end
  end
end
