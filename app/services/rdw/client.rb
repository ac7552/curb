module Rdw
  # Dutch vehicle register and APK (inspection) defects by plate. CC-0 open data, no key.
  # https://opendata.rdw.nl
  class Client
    URL = "https://opendata.rdw.nl/resource/"
    VEHICLES = "m9d7-ebf2.json"
    FUEL = "8ys7-d773.json"
    DEFECTS = "a34c-vvps.json"
    DEFECT_NAMES = "hx2c-gt7k.json"

    def initialize(connection: HttpClient.build(URL)) = @connection = connection

    def vehicle(plate)
      row = HttpClient.get(@connection, VEHICLES, { kenteken: plate }).first
      return unless row

      fuel = HttpClient.get(@connection, FUEL, { kenteken: plate }).first
      cc = row["cilinderinhoud"].to_i
      VehicleMatch.new(
        source: "RDW",
        make: row["merk"].to_s.titleize,
        model: row["handelsbenaming"].to_s,
        engine: cc.positive? ? format("%.1fL", cc / 1000.0) : nil,
        fuel_type: fuel&.dig("brandstof_omschrijving"),
        first_used_on: parse_date(row["datum_eerste_toelating"]),
        history: { source: "RDW", defects: defects(plate) }
      )
    end

    # Defects found at APK inspections, newest first, with the RDW's (Dutch) descriptions.
    def defects(plate)
      rows = HttpClient.get(@connection, DEFECTS, { kenteken: plate, "$order" => "meld_datum_door_keuringsinstantie DESC", "$limit" => 50 })
      return [] if rows.empty?

      ids = rows.map { |row| row["gebrek_identificatie"] }.uniq
      where = "gebrek_identificatie in(#{ids.map { |id| "'#{id.gsub(/[^A-Za-z0-9]/, "")}'" }.join(",")})"
      names = HttpClient.get(@connection, DEFECT_NAMES, { "$where" => where })
                        .to_h { |row| [ row["gebrek_identificatie"], row["gebrek_omschrijving"] ] }

      rows.map do |row|
        { text: names.fetch(row["gebrek_identificatie"], row["gebrek_identificatie"]),
          found_on: parse_date(row["meld_datum_door_keuringsinstantie"])&.iso8601,
          count: row["aantal_gebreken_geconstateerd"].to_i }
      end
    end

    private
      def parse_date(value)
        Date.strptime(value.to_s[0, 8], "%Y%m%d") if value.to_s.match?(/\A\d{8}/)
      end
  end
end
