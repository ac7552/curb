# Maps NHTSA's component names ("POWER TRAIN:AUTOMATIC TRANSMISSION:TORQUE CONVERTER") to Curb's
# defect categories. Most specific rule first; nil means the component isn't a repair we price
# (unknown, child seats, and so on).
module NhtsaComponent
  RULES = [
    [ /HYBRID|ELECTRIC PROPULSION|PROPULSION BATTERY|HIGH VOLTAGE/, "hybrid-battery" ],
    [ /ANTILOCK|ANTI-LOCK|ELECTRONIC STABILITY/, "abs" ],
    [ /PARKING BRAKE/, "parking-brake" ],
    [ /SERVICE BRAKES/, "brake-hydraulics" ],
    [ /COOLING SYSTEM|RADIATOR|WATER PUMP|THERMOSTAT/, "cooling" ],
    [ /OIL LEAK/, "oil-leaks" ],
    [ /\AENGINE/, "engine" ],
    [ /DRIVELINE|DRIVE SHAFT|AXLE|CV JOINT/, "drive-shafts" ],
    [ /POWER TRAIN|TRANSMISSION|CLUTCH/, "transmission" ],
    [ /FUEL/, "fuel-system" ],
    [ /EXHAUST|EMISSION|CATALYTIC/, "emissions" ],
    [ /AIR BAGS|SEAT BELTS|\ASEATS/, "restraints" ],
    [ /STEERING/, "steering" ],
    [ /SUSPENSION/, "suspension" ],
    [ /WHEELS:HUB|WHEEL BEARING/, "wheel-bearings" ],
    [ /\ATIRES/, "tyres" ],
    [ /EXTERIOR LIGHTING|HEADLIGHT/, "lights" ],
    [ /WIPER|WASHER/, "wipers" ],
    [ /VISIBILITY|MIRROR|GLASS/, "glass-mirrors" ],
    [ /STRUCTURE.*(CORROSION|RUST)/, "body-corrosion" ],
    [ /STRUCTURE|LATCHES|LOCKS|DOORS/, "body" ],
    [ /AIR CONDITION|HEATER|CLIMATE|HVAC/, "hvac" ],
    [ /ELECTRICAL|FORWARD COLLISION|LANE DEPARTURE|BACK OVER|VEHICLE SPEED CONTROL|COMMUNICATION/, "electrical" ]
  ].freeze

  module_function

  def category_slug(component)
    text = component.to_s.upcase.strip
    RULES.find { |pattern, _| text.match?(pattern) }&.last
  end
end
