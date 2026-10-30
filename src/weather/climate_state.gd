class_name ClimateState
extends RefCounted
## Dynamic environmental state shared by all systems. TimeController and
## WeatherSystem WRITE it every frame; biology, ecosystem, AI and rendering
## READ it through the sampling functions below (positions in world space).

var world: WorldData

# --- Written by TimeController -------------------------------------------------
var bio_time: float = 0.0        # biological seconds since world creation
var day: int = 0
var hour: float = 8.0            # 0..24
var season: int = 0              # 0 spring, 1 summer, 2 autumn, 3 winter
var year_phase: float = 0.0      # 0..1 through the year (0 = start of spring)
var sun_elevation: float = 30.0  # degrees
var daylight: float = 1.0        # 0 night .. 1 full day (before clouds)
var sun_direction := Vector3(0.0, 0.5, 0.87)  # unit vector towards the sun (world space)

# --- Written by WeatherSystem --------------------------------------------------
var weather: StringName = &"clear"   # clear cloudy rain storm fog snow
var cloud_cover: float = 0.1     # 0..1
var precipitation: float = 0.0   # 0..1 intensity
var fog: float = 0.0             # 0..1
var wind := Vector2(1.0, 0.0)    # m/s, world xz
var weather_temp_offset: float = 0.0   # °C anomaly from weather fronts
var drought: float = 0.0         # 0..1 accumulated dryness index
var snow_cover: float = 0.0      # 0..1 fresh snow lying where it is below freezing
var wetness: float = 0.0         # 0..1 surface wetness after rain (dries out)
var regional_temperature: float = 15.0  # °C near the observer (written by WeatherSystem)

# --- Sandbox controls (player experiments) ------------------------------------
var sandbox_temp_offset: float = 0.0
var sandbox_moisture_offset: float = 0.0
var sandbox_resource_mult: float = 1.0

const SEASON_AMPLITUDE := 9.0    # °C, continental seasonal swing
const DIURNAL_AMPLITUDE := 4.5   # °C day/night swing under clear sky
const LAPSE_RATE := 0.0065       # °C per metre (already in base grid; used for flyers)


## Seasonal temperature anomaly (°C): warmest mid-summer (phase 0.375),
## coldest mid-winter (phase 0.875).
func seasonal_offset() -> float:
	return cos((year_phase - 0.375) * TAU) * SEASON_AMPLITUDE * 0.5


func diurnal_offset() -> float:
	return sin((hour - 9.0) / 24.0 * TAU) * DIURNAL_AMPLITUDE * (1.0 - 0.6 * cloud_cover)


## Air (or water) temperature at a position, °C.
func temperature_at(p: Vector3) -> float:
	var base := 15.0
	var in_water := false
	if world != null:
		base = world.base_temperature_at(p.x, p.z)
		var ground := world.height_at(p.x, p.z)
		in_water = world.water_depth_at(p.x, p.z) > 0.05 and p.y < world.water_surface_at(p.x, p.z)
		# Flyers above the ground get the lapse rate.
		base -= maxf(0.0, p.y - ground) * LAPSE_RATE
	var t := base + seasonal_offset() + weather_temp_offset + sandbox_temp_offset
	if in_water:
		# Water is thermally inert: half the seasonal swing, no diurnal swing, never below -1.8.
		return maxf(-1.8, base + seasonal_offset() * 0.5 + sandbox_temp_offset)
	return t + diurnal_offset()


## Relative humidity / substrate moisture 0..1.
func humidity_at(p: Vector3) -> float:
	var m := 0.5
	if world != null:
		m = world.moisture_at(p.x, p.z)
	return clampf(m + precipitation * 0.3 - drought * 0.35 + sandbox_moisture_offset, 0.0, 1.0)


## Light level 0..1 at a position (before vegetation shade).
func light_at(p: Vector3) -> float:
	var l := daylight * (1.0 - 0.55 * cloud_cover) * (1.0 - 0.5 * fog)
	if world != null:
		var depth := world.water_surface_at(p.x, p.z) - p.y
		if world.water_depth_at(p.x, p.z) > 0.05 and depth > 0.0:
			l *= exp(-depth * 0.12)
	return clampf(maxf(l, 0.02), 0.0, 1.0)


func is_night() -> bool:
	return daylight < 0.15


## Oxygen availability 0..1 in the medium at p.
func oxygen_at(p: Vector3, in_water: bool) -> float:
	if in_water:
		# Warm water holds less dissolved oxygen.
		return clampf(1.0 - maxf(0.0, temperature_at(p) - 4.0) * 0.018, 0.25, 1.0)
	var alt := p.y - (world.sea_level if world != null else 0.0)
	return clampf(exp(-maxf(alt, 0.0) / 8000.0), 0.3, 1.0)


## Snow lying at a position 0..1 (fresh cover where cold + permanent glaciers).
func snow_at(p: Vector3) -> float:
	var t := temperature_at(p) - diurnal_offset()
	var fresh := snow_cover * clampf((1.5 - t) / 2.5, 0.0, 1.0)
	var permanent := clampf((-4.0 - t) / 4.0, 0.0, 1.0)
	return clampf(fresh + permanent, 0.0, 1.0)


## True when precipitation at p falls as snow.
func precipitation_is_snow(p: Vector3) -> bool:
	return temperature_at(p) < 0.5


func is_breeding_season() -> bool:
	return season == 0 or (season == 1 and year_phase < 0.35)


func to_dict() -> Dictionary:
	return {
		"weather": str(weather), "cloud_cover": cloud_cover, "precipitation": precipitation, "fog": fog,
		"wind": Serial.v2(wind), "weather_temp_offset": weather_temp_offset, "drought": drought,
		"snow_cover": snow_cover, "wetness": wetness,
		"sandbox_temp_offset": sandbox_temp_offset, "sandbox_moisture_offset": sandbox_moisture_offset,
		"sandbox_resource_mult": sandbox_resource_mult,
	}


func from_dict(d: Dictionary) -> void:
	weather = Serial.sn(d, "weather", &"clear")
	cloud_cover = Serial.f(d, "cloud_cover", 0.1)
	precipitation = Serial.f(d, "precipitation", 0.0)
	fog = Serial.f(d, "fog", 0.0)
	wind = Serial.to_v2(d.get("wind"), Vector2(1, 0))
	weather_temp_offset = Serial.f(d, "weather_temp_offset", 0.0)
	drought = Serial.f(d, "drought", 0.0)
	snow_cover = Serial.f(d, "snow_cover", 0.0)
	wetness = Serial.f(d, "wetness", 0.0)
	sandbox_temp_offset = Serial.f(d, "sandbox_temp_offset", 0.0)
	sandbox_moisture_offset = Serial.f(d, "sandbox_moisture_offset", 0.0)
	sandbox_resource_mult = Serial.f(d, "sandbox_resource_mult", 1.0)
