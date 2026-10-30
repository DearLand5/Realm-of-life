class_name WeatherSystem
extends Node
## Regional weather driven by WeatherModel (Markov chain over clear / cloudy /
## rain / storm / fog / snow, modulated by season and the climate around the
## focus point). Writes ClimateState weather fields every frame in biological
## time: cloud_cover, precipitation, fog, wind (with gusts), weather_temp_offset,
## drought (heat without rain), snow_cover (builds below freezing), wetness.
## Emits EventBus.weather_changed. Visual effects (rain/snow particles,
## lightning) live in a WeatherFX child that follows the camera.
##   setup(climate, world, time_controller = null, camera = null, seed = 1)

signal lightning(position: Vector3)

var climate: ClimateState
var world: WorldData
var time: TimeController
var camera: Camera3D
## Region whose climate drives transitions (camera target / observed creature).
var focus := Vector3.ZERO
var state: StringName = &"clear"
var hours_left: float = 8.0
## 0..1 flash brightness, read by DayNightCycle.
var lightning_flash: float = 0.0
var visuals_enabled := true
var fx: WeatherFX

var _rng := Rng.new(1)
var _wind_angle: float = 0.6
var _wind_speed: float = 2.5
var _phys_time: float = 0.0


func _init() -> void:
	process_priority = -90


func setup(shared: ClimateState, w: WorldData, clock: TimeController = null, cam: Camera3D = null, seed_value: int = 1) -> void:
	climate = shared
	world = w
	time = clock
	camera = cam
	_rng = Rng.new(seed_value if seed_value != 0 else 1)
	_wind_angle = _rng.range_f(0.0, TAU)
	if not WeatherModel.is_valid(climate.weather):
		climate.weather = &"clear"
	state = climate.weather
	hours_left = WeatherModel.duration_hours(state, _rng)
	if visuals_enabled and fx == null and is_inside_tree():
		_make_fx()


func _ready() -> void:
	if visuals_enabled and fx == null and climate != null:
		_make_fx()


func _make_fx() -> void:
	fx = WeatherFX.new()
	fx.name = "WeatherFX"
	add_child(fx)
	fx.setup(self)


func _process(delta: float) -> void:
	if climate == null:
		return
	var bio_dt := time.bio_dt if time != null else delta * Units.BIO_TIME_RATIO
	if camera != null and is_instance_valid(camera):
		focus = camera.global_position
	_phys_time += delta
	advance(bio_dt)
	_update_gusts()
	if fx != null:
		fx.update_fx(delta)


## Advances the weather by `bio_dt` biological seconds (tests call this directly).
func advance(bio_dt: float) -> void:
	if climate == null or bio_dt <= 0.0:
		return
	var hours := bio_dt / Units.SECONDS_PER_HOUR
	var region := _region()
	var temp: float = region["temp"]
	var moist: float = region["moist"]
	climate.regional_temperature = temp + climate.diurnal_offset() + climate.weather_temp_offset
	# Markov transitions (bounded loop for huge time steps).
	hours_left -= hours
	var guard := 0
	while hours_left <= 0.0 and guard < 64:
		guard += 1
		_set_state(WeatherModel.next_state(state, climate.season, temp + climate.weather_temp_offset, moist, _rng))
		hours_left += WeatherModel.duration_hours(state, _rng)
	if guard >= 64:
		hours_left = WeatherModel.duration_hours(state, _rng)
	# Rain falling below freezing becomes snow (and vice versa).
	if state == &"rain" and climate.regional_temperature < -0.5:
		_set_state(&"snow")
	elif state == &"snow" and climate.regional_temperature > 2.5:
		_set_state(&"rain")
	_relax(hours)
	_accumulate(hours, moist)


func _region() -> Dictionary:
	var t := 15.0
	var m := 0.5
	if world != null:
		var p := world.clamp_xz(focus)
		t = world.base_temperature_at(p.x, p.z)
		m = world.moisture_at(p.x, p.z)
	t += climate.seasonal_offset() + climate.sandbox_temp_offset
	m = clampf(m + climate.sandbox_moisture_offset, 0.0, 1.0)
	return {"temp": t, "moist": m}


## Eases the atmosphere toward the current state's targets.
func _relax(hours: float) -> void:
	var tg := WeatherModel.target(state)
	var c := climate
	c.cloud_cover = lerpf(c.cloud_cover, float(tg["cloud"]), 1.0 - exp(-0.9 * hours))
	c.precipitation = lerpf(c.precipitation, float(tg["precip"]), 1.0 - exp(-1.4 * hours))
	c.fog = lerpf(c.fog, float(tg["fog"]), 1.0 - exp(-0.8 * hours))
	c.weather_temp_offset = lerpf(c.weather_temp_offset, float(tg["temp"]), 1.0 - exp(-0.25 * hours))
	_wind_speed = lerpf(_wind_speed, float(tg["wind"]), 1.0 - exp(-0.7 * hours))
	# Wind direction wanders slowly.
	_wind_angle = wrapf(_wind_angle + _rng.gauss(0.0, 0.12) * sqrt(minf(hours, 24.0)), -PI, PI)


## Drought, snow cover and wetness — the slow fields biology/ecosystem read.
func _accumulate(hours: float, moist: float) -> void:
	var c := climate
	var t := c.regional_temperature
	var rain := c.precipitation if t >= 0.5 else 0.0
	var snowfall := c.precipitation if t < 0.5 else 0.0
	var days := hours / 24.0
	var heat := clampf((t - 8.0) / 22.0, 0.0, 1.0)
	var dry_rate := 0.07 * heat * (1.0 - 0.5 * c.cloud_cover) * (1.15 - 0.6 * moist)
	c.drought = clampf(c.drought + (dry_rate - rain * 1.6 - c.wetness * 0.05) * days, 0.0, 1.0)
	c.snow_cover = clampf(c.snow_cover + snowfall * 0.1 * hours - maxf(0.0, t - 0.5) * 0.012 * hours * (1.0 + rain * 3.0), 0.0, 1.0)
	c.wetness = clampf(c.wetness + rain * 0.6 * hours - hours * (0.04 + 0.08 * heat) * (1.0 - 0.6 * c.cloud_cover) * (1.0 - rain), 0.0, 1.0)


## Gusts in real time so plants and particles move naturally at any time scale.
func _update_gusts() -> void:
	var t := _phys_time
	var gust := 0.22 * sin(t * 0.63) * sin(t * 1.71 + 1.3) + 0.12 * sin(t * 2.9 + 0.4)
	if state == &"storm":
		gust *= 2.2
	var speed := maxf(0.0, _wind_speed * (1.0 + gust))
	climate.wind = Vector2(cos(_wind_angle), sin(_wind_angle)) * speed


func _set_state(s: StringName) -> void:
	if not WeatherModel.is_valid(s) or s == state:
		return
	state = s
	climate.weather = s
	EventBus.weather_changed.emit(s)


## Sandbox/preview control: switch weather now. immediate snaps the atmosphere.
func force_weather(s: StringName, immediate: bool = true, duration_hours: float = 6.0) -> void:
	if not WeatherModel.is_valid(s):
		push_warning("WeatherSystem: unknown weather '%s'" % s)
		return
	_set_state(s)
	climate.weather = s
	hours_left = maxf(duration_hours, 0.5)
	if immediate:
		var tg := WeatherModel.target(s)
		climate.cloud_cover = tg["cloud"]
		climate.precipitation = tg["precip"]
		climate.fog = tg["fog"]
		climate.weather_temp_offset = tg["temp"]
		_wind_speed = tg["wind"]
		_update_gusts()


## Called by WeatherFX when a bolt strikes.
func notify_lightning(pos: Vector3) -> void:
	lightning.emit(pos)


func label() -> String:
	return WeatherModel.label(state)


func to_dict() -> Dictionary:
	return {
		"state": str(state), "hours_left": hours_left, "wind_angle": _wind_angle,
		"wind_speed": _wind_speed, "rng": _rng.get_state(),
	}


func from_dict(d: Dictionary) -> void:
	var s := Serial.sn(d, "state", &"clear")
	state = s if WeatherModel.is_valid(s) else &"clear"
	if climate != null:
		climate.weather = state
	hours_left = maxf(0.1, Serial.f(d, "hours_left", 6.0))
	_wind_angle = Serial.f(d, "wind_angle", 0.6)
	_wind_speed = Serial.f(d, "wind_speed", 2.5)
	if d.has("rng"):
		_rng.set_state(Serial.i(d, "rng", 1))
