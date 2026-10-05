require "csv"

module Curb
  # Writes synthetic files in the DVSA anonymised MOT format so the whole pipeline (COPY import,
  # categorizing, rate views, calculator) runs before the real downloads are in place.
  #
  # The numbers are made up: every model follows the same age and mileage curve, nudged by a few
  # per-model multipliers. Never show them to buyers as real odds.
  class DemoMotFiles
    MODELS = [
      [ "HONDA", "CIVIC", [ [ 1799, "PE" ], [ 2199, "DI" ] ], 0.80, { "suspension" => 0.9 } ],
      [ "HONDA", "CR-V", [ [ 1997, "PE" ], [ 2199, "DI" ] ], 0.85, { "hvac" => 1.5 } ],
      [ "HONDA", "JAZZ", [ [ 1339, "PE" ] ], 0.75, {} ],
      [ "TOYOTA", "COROLLA", [ [ 1598, "PE" ], [ 1798, "HY" ] ], 0.70, {} ],
      [ "TOYOTA", "RAV4", [ [ 1987, "PE" ], [ 2494, "HY" ] ], 0.75, { "body-corrosion" => 1.4 } ],
      [ "TOYOTA", "YARIS", [ [ 998, "PE" ], [ 1497, "HY" ] ], 0.70, {} ],
      [ "TOYOTA", "PRIUS", [ [ 1798, "HY" ] ], 0.70, { "hybrid-battery" => 3.0 } ],
      [ "FORD", "FOCUS", [ [ 999, "PE" ], [ 1596, "PE" ], [ 1997, "DI" ] ], 1.15, { "springs" => 1.8, "suspension" => 1.3 } ],
      [ "FORD", "FIESTA", [ [ 999, "PE" ], [ 1242, "PE" ] ], 1.10, { "springs" => 1.6, "lights" => 1.2 } ],
      [ "VOLKSWAGEN", "GOLF", [ [ 1395, "PE" ], [ 1968, "DI" ] ], 1.00, { "emissions" => 1.3 } ],
      [ "VOLKSWAGEN", "POLO", [ [ 999, "PE" ], [ 1198, "PE" ] ], 1.00, {} ],
      [ "NISSAN", "QASHQAI", [ [ 1197, "PE" ], [ 1461, "DI" ] ], 1.20, { "brake-hydraulics" => 1.4, "wheel-bearings" => 1.5 } ],
      [ "NISSAN", "JUKE", [ [ 1598, "PE" ] ], 1.15, { "suspension" => 1.3 } ],
      [ "VAUXHALL", "CORSA", [ [ 1229, "PE" ], [ 1398, "PE" ] ], 1.25, { "springs" => 1.5, "lights" => 1.3 } ],
      [ "VAUXHALL", "ASTRA", [ [ 1398, "PE" ], [ 1598, "DI" ] ], 1.25, { "suspension" => 1.3, "brake-hydraulics" => 1.2 } ],
      [ "BMW", "3 SERIES", [ [ 1995, "DI" ], [ 1998, "PE" ] ], 1.10, { "suspension" => 1.4, "electrical" => 1.4, "cooling" => 1.6 } ],
      [ "KIA", "SPORTAGE", [ [ 1685, "DI" ], [ 1591, "PE" ] ], 0.90, {} ],
      [ "HYUNDAI", "TUCSON", [ [ 1685, "DI" ], [ 1591, "PE" ] ], 0.90, { "springs" => 1.3 } ],
      [ "SKODA", "OCTAVIA", [ [ 1598, "DI" ], [ 1395, "PE" ] ], 0.95, {} ]
    ].freeze

    # [fail wording, advisory wording, yearly chance at the reference age and mileage]
    DEFECTS = {
      "lights" => [ "Headlamp aim too low", "Headlamp lens slightly damaged", 0.090 ],
      "tyres" => [ "Tyre tread depth below requirements of 1.6mm", "Tyre worn close to legal limit", 0.110 ],
      "brake-wear" => [ "Brake disc significantly and obviously worn", "Brake pad(s) wearing thin", 0.080 ],
      "brake-hydraulics" => [ "Brake pipe excessively corroded", "Brake hose deteriorated", 0.035 ],
      "suspension" => [ "Suspension arm pin or bush excessively worn", "Anti-roll bar linkage ball joint dust cover damaged", 0.060 ],
      "springs" => [ "Coil spring fractured or seriously weakened", "Coil spring corroded", 0.030 ],
      "shock-absorbers" => [ "Shock absorber has a serious fluid leak", "Shock absorber misting", 0.025 ],
      "steering" => [ "Track rod end ball joint has excessive wear", "Steering rack gaiter split", 0.020 ],
      "wheel-bearings" => [ "Wheel bearing has excessive play", "Wheel bearing slightly rough", 0.012 ],
      "drive-shafts" => [ "Constant velocity joint gaiter missing", "Drive shaft joint constant velocity boot damaged", 0.022 ],
      "exhaust" => [ "Exhaust has a major leak of exhaust gases", "Exhaust has a minor leak of exhaust gases", 0.025 ],
      "emissions" => [ "Emissions exceed the manufacturer's specified limits", "Catalytic converter heat shield insecure", 0.018 ],
      "oil-leaks" => [ "Engine has an oil leak which is excessive", "Oil leak, but not excessive", 0.030 ],
      "warning-lights" => [ "Engine malfunction indicator lamp inoperative", "Malfunction indicator lamp illuminated intermittently", 0.012 ],
      "body-corrosion" => [ "Sub-frame excessively corroded", "Sill corroded but not seriously weakened", 0.020 ],
      "body" => [ "Door does not open from outside", "Bumper insecure", 0.010 ],
      "wipers" => [ "Wiper blade defective", "Washer does not provide sufficient liquid", 0.040 ],
      "glass-mirrors" => [ "Windscreen damage in zone A over 10mm", "Windscreen chipped outside zone A", 0.020 ],
      "restraints" => [ "Seat belt webbing damaged", "Airbag warning lamp illuminated intermittently", 0.006 ],
      "fuel-system" => [ "Fuel pipe leaking", "Fuel pipe slightly corroded", 0.004 ],
      "cooling" => [ "Radiator has a coolant leak affecting the environment", "Coolant leak, not excessive", 0.006 ],
      "electrical" => [ "Battery insecure and likely to fall from its carrier", "Electrical wiring not adequately secured", 0.008 ],
      "hvac" => [ "Heater or demister does not clear the screen", "Air conditioning not working", 0.004 ],
      "hybrid-battery" => [ "Hybrid system warning lamp indicates a malfunction", "High voltage cable insecure", 0.004 ],
      "plates-id" => [ "Registration plate deteriorated and likely to be misread", "Registration plate faded", 0.008 ],
      "horn" => [ "Horn not working", "Horn tone not continuous", 0.004 ]
    }.freeze

    def initialize(dir, vehicles_per_model: 700, seed: 42, through: Date.new(2026, 6, 30))
      @dir = Pathname(dir)
      @vehicles_per_model = vehicles_per_model
      @random = Random.new(seed)
      @through = through
    end

    # Writes the three files and returns their paths, ready for Importers::MotBulk.new(**paths).
    def write
      @dir.mkpath
      paths = { results: @dir.join("test_result.csv"), items: @dir.join("test_item.csv"), details: @dir.join("item_detail.csv") }
      write_details(paths[:details])
      CSV.open(paths[:results], "w", col_sep: "|") do |results|
        CSV.open(paths[:items], "w", col_sep: "|") do |items|
          results << Importers::MotBulk::COLUMNS[:results]
          items << Importers::MotBulk::COLUMNS[:items]
          write_tests(results, items)
        end
      end
      paths.transform_values(&:to_s)
    end

    private
      def rfr_ids
        @rfr_ids ||= DEFECTS.keys.each_with_index.to_h { |slug, index| [ slug, [ 1000 + index * 2, 1001 + index * 2 ] ] }
      end

      def write_details(path)
        CSV.open(path, "w", col_sep: "|") do |csv|
          csv << Importers::MotBulk::COLUMNS[:details]
          DEFECTS.each do |slug, (fail_text, advisory_text, _)|
            fail_id, advisory_id = rfr_ids[slug]
            csv << [ fail_id, 4, nil, "N", fail_text, nil, nil, nil, nil ]
            csv << [ advisory_id, 4, nil, "N", nil, nil, nil, advisory_text, nil ]
          end
        end
      end

      def write_tests(results, items)
        test_id = 0
        vehicle_id = 0
        MODELS.each do |make, model, engines, reliability, extra|
          @vehicles_per_model.times do
            vehicle_id += 1
            cc, fuel = engines.sample(random: @random)
            first_use = Date.new(2008 + @random.rand(13), 1 + @random.rand(12), 1 + @random.rand(28))
            miles_per_year = (4_000 + @random.rand(12_000)) * (fuel == "DI" ? 1.3 : 1.0)
            (3..20).each do |age|
              tested_on = first_use >> (12 * age)
              break if tested_on > @through
              mileage = (miles_per_year * age * (0.85 + @random.rand * 0.3)).round
              test_id += 1
              found = defects_for(age:, mileage:, reliability:, extra:, fuel:)
              result = found.any? { |_, kind| kind == "F" } ? (@random.rand < 0.3 ? "PRS" : "F") : "P"
              results << [ test_id, vehicle_id, tested_on.iso8601, 4, "NT", result, mileage, "XX", make, model,
                           "SILVER", fuel, cc, first_use.iso8601 ]
              found.each { |rfr_id, kind| items << [ test_id, rfr_id, kind, nil, nil ] }
            end
          end
        end
      end

      def defects_for(age:, mileage:, reliability:, extra:, fuel:)
        wear = (0.45 + 0.11 * age) * (0.75 + [ mileage, 150_000 ].min / 150_000.0 * 0.5)
        DEFECTS.filter_map do |slug, (_, _, base)|
          chance = base * wear * reliability * extra.fetch(slug, 1.0)
          chance *= 1.5 if slug == "emissions" && fuel == "DI"
          chance = 0 if slug == "hybrid-battery" && fuel != "HY"
          next unless @random.rand < chance
          fail_id, advisory_id = rfr_ids[slug]
          @random.rand < 0.45 ? [ fail_id, "F" ] : [ advisory_id, "A" ]
        end
      end
  end
end
