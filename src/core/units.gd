class_name Units
extends RefCounted
## Physical and simulation constants. All quantities are SI unless noted.
##
## TIME MODEL (documented game simplification):
##   * "physical time" drives motion/animation and runs at real time × time_scale;
##   * "biological time" drives metabolism, growth, aging, plants, weather and
##     runs BIO_TIME_RATIO times faster than physical time.
##   One physical second == BIO_TIME_RATIO biological seconds (1 game minute),
##   so a game day lasts 24 real minutes at ×1.
##   All biological rates in code are expressed per biological second.

const BIO_TIME_RATIO := 60.0
const SECONDS_PER_HOUR := 3600.0
const SECONDS_PER_DAY := 86400.0
const DAYS_PER_SEASON := 10
const SEASONS_PER_YEAR := 4
const DAYS_PER_YEAR := DAYS_PER_SEASON * SEASONS_PER_YEAR

const GRAVITY := 9.81
const AIR_DENSITY := 1.225        # kg/m^3 at sea level
const WATER_DENSITY := 1000.0     # kg/m^3
const TISSUE_DENSITY := 1050.0    # kg/m^3, soft tissue average
const BONE_STRESS_LIMIT := 2.0e7  # Pa, simplified safe bone stress
const MUSCLE_STRESS := 2.5e5      # Pa, max isometric muscle stress (~25 N/cm^2)
const MUSCLE_POWER_PER_KG := 150.0 # W per kg of muscle, sustained-burst average
const FAT_ENERGY := 3.7e7         # J/kg
const PLANT_ENERGY := 6.0e6       # J/kg wet plant matter (average)
const MEAT_ENERGY := 7.0e6        # J/kg wet meat
const KLEIBER_COEF := 3.4         # W per kg^0.75 (mammal-like endotherm BMR)
const ECTOTHERM_FACTOR := 0.15    # ectotherm BMR relative to endotherm at 20 C
const O2_PER_JOULE := 5.0e-8      # kg O2 per joule (approximate)
const KELVIN := 273.15

const SEASON_NAMES := ["Весна", "Лето", "Осень", "Зима"]


static func season_of_day(day: int) -> int:
	return int(floor(float(day) / DAYS_PER_SEASON)) % SEASONS_PER_YEAR
