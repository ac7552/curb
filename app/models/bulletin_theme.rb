# Known failure themes, found by matching service bulletin titles ("DPS6 transmission shudder",
# "Coolant pump inoperative"). Each theme belongs to one of our part categories, so bulletin evidence
# can sit next to inspection and complaint evidence for the same part.
module BulletinTheme
  # fuels: fuel letters (see VehicleName::FUEL_CODES) a theme applies to; nil for every car.
  Theme = Data.define(:slug, :label, :category, :pattern, :fuels)

  FUELS = {
    "dpf" => %w[D], "egr" => %w[D], "diesel-exhaust-fluid" => %w[D],
    "hybrid-battery" => %w[H E], "charging" => %w[H E],
    "ignition" => %w[P H], "carbon-buildup" => %w[P H], "timing-chain" => %w[P D H], "turbo" => %w[P D H]
  }.freeze

  THEMES = [
    [ "timing-chain", "the timing chain or belt", "engine", /timing (chain|belt)|chain (guide|tensioner)/i ],
    [ "oil-consumption", "burning too much oil", "engine", /oil consumption|consum\w* (excessive )?oil|excessive oil/i ],
    [ "oil-filter-housing", "oil filter housing leaks", "oil-leaks", /oil filter housing/i ],
    [ "valve-cover", "valve cover leaks", "oil-leaks", /valve cover|cylinder head cover|rocker cover/i ],
    [ "crankcase-vent", "the crankcase vent (PCV)", "engine", /crankcase|\bpcv\b|oil separator/i ],
    [ "head-gasket", "the head gasket", "engine", /head gasket/i ],
    [ "carbon-buildup", "carbon build-up", "engine", /carbon (build|deposit)|intake valve deposit/i ],
    [ "cam-timing", "cam timing (VANOS / cam phasers)", "engine", /vanos|camshaft (adjuster|phaser|actuator)|cam phaser|variable valve timing/i ],
    [ "turbo", "the turbo", "engine", /turbo|wastegate/i ],
    [ "fuel-pump", "the fuel pump", "fuel-system", /fuel pump/i ],
    [ "injectors", "fuel injectors", "fuel-system", /injector/i ],
    [ "ignition", "misfires, coils or spark plugs", "engine", /ignition coil|spark plug|misfire/i ],
    [ "engine-mounts", "engine mounts", "engine", /engine mount/i ],
    [ "water-pump", "the water pump", "cooling", /water pump|coolant pump/i ],
    [ "thermostat", "the thermostat", "cooling", /thermostat/i ],
    [ "coolant-leak", "coolant leaks", "cooling", /coolant (leak|loss)|low coolant|coolant level/i ],
    [ "radiator", "the radiator or coolant tank", "cooling", /radiator|expansion tank|coolant reservoir/i ],
    [ "overheating", "overheating", "cooling", /overheat/i ],
    [ "shifting", "rough or slipping gear shifts", "transmission", /harsh (shift|engagement)|shift (quality|flare|delay)|shudder|slip(s|ping)?\b/i ],
    [ "transmission-control", "the transmission's control unit", "transmission", /mechatronic|valve body|transmission control module|\btcm\b/i ],
    [ "clutch", "the clutch or flywheel", "transmission", /clutch|dual.?mass flywheel/i ],
    [ "cvt", "the CVT gearbox", "transmission", /\bcvt\b|continuously variable/i ],
    [ "differential", "the differential or transfer case", "drive-shafts", /transfer case|differential/i ],
    [ "dpf", "the diesel particulate filter", "emissions", /particulate|\bdpf\b/i ],
    [ "egr", "the EGR valve", "emissions", /\begr\b|exhaust gas recirc/i ],
    [ "diesel-exhaust-fluid", "the AdBlue / DEF system", "emissions", /\bdef\b|adblue|urea|nox sensor/i ],
    [ "catalytic-converter", "the catalytic converter", "emissions", /catalytic|catalyst/i ],
    [ "battery-drain", "the battery going flat", "electrical", /battery (drain|discharge)|parasitic|12.?v battery/i ],
    [ "infotainment", "the screen, radio or navigation", "electrical", /idrive|infotainment|navigation|radio|touch ?screen|display (blank|black|freez)|bluetooth|carplay/i ],
    [ "keyless", "the key or keyless entry", "electrical", /key (not detected|fob)|keyless/i ],
    [ "window-regulator", "power windows", "body", /window regulator|power window/i ],
    [ "water-leak", "water leaks inside the car", "body", /water (leak|intrusion|ingress)|sunroof (drain|leak)/i ],
    [ "air-suspension", "the air suspension", "shock-absorbers", /air suspension|air spring/i ],
    [ "shocks", "shock absorbers", "shock-absorbers", /shock absorber|\bstrut\b/i ],
    [ "control-arms", "control arms and bushes", "suspension", /control arm|bushing|ball joint|thrust (arm|link)/i ],
    [ "steering-rack", "the steering rack", "steering", /steering (rack|gear)|power steering|electric steering/i ],
    [ "hybrid-battery", "the hybrid or electric battery", "hybrid-battery", /high.?voltage battery|hybrid battery|traction battery|battery (module|pack)/i ],
    [ "charging", "charging", "hybrid-battery", /charg(ing|er)\b|charge port/i ],
    [ "air-conditioning", "the air conditioning or heater", "hvac", %r{a/?c compressor|air condition|refrigerant|evaporator|heater core|blower}i ],
    [ "evap", "fuel vapor (EVAP) leaks", "fuel-system", /\bevap\b|purge valve|charcoal canister/i ]
  ].map { |slug, label, category, pattern| Theme.new(slug:, label:, category:, pattern:, fuels: FUELS[slug]) }.freeze

  BY_SLUG = THEMES.index_by(&:slug).freeze

  module_function

  def find(slug) = BY_SLUG[slug.to_s]

  # Whether a theme can apply to a car with this engine key ("2.0-P", "EV"); unknown engines allow all.
  def applies?(slug, engine_key)
    fuels = find(slug)&.fuels
    fuel = engine_key == "EV" ? "E" : engine_key.to_s[/-([A-Z])\z/, 1]
    fuels.nil? || fuel.nil? || fuels.include?(fuel)
  end

  def match(title)
    THEMES.select { |theme| title.to_s.match?(theme.pattern) }.map(&:slug)
  end

  # Tags every bulletin with the themes its title matches. Titles repeat across cars, so each distinct
  # title is matched once. Returns the number of rows updated.
  def tag_all!
    ServiceBulletin.distinct.pluck(:title).group_by { |title| match(title) }.sum do |themes, titles|
      titles.each_slice(1_000).sum do |slice|
        ServiceBulletin.where(title: slice).where.not(themes:).update_all(themes:)
      end
    end
  end
end
