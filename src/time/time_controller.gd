class_name TimeController
extends Node
## Owns the simulation clock. Each frame it computes
##   phys_dt = real delta × time_scale (0 when paused)  — motion/animation;
##   bio_dt  = phys_dt × Units.BIO_TIME_RATIO            — biology/weather,
## and writes calendar + sun fields into the shared ClimateState.
## Emits EventBus.hour_changed / day_changed / season_changed / time_scale_changed.
## Processes early (process_priority −100) so other systems read fresh dt.

const SCALES: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 64.0, 256.0, 1024.0, 4096.0]
const DEFAULT_SCALE_INDEX := 2
## Real-time delta is clamped so a hitch never fast-forwards the world.
const MAX_REAL_DELTA := 0.1
const MAX_HOUR_SIGNALS_PER_FRAME := 48

var climate: ClimateState
var scale_index: int = DEFAULT_SCALE_INDEX
var time_scale: float = 1.0
var paused := false
var latitude: float = 42.0       # degrees north, drives sun path and day length
var phys_dt: float = 0.0
var bio_dt: float = 0.0

var _last_hour: int = -1
var _last_day: int = -1
var _last_season: int = -1


func _init() -> void:
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS


## climate: shared state to write (created if null). start_hour: 0..24 for new worlds.
func setup(shared: ClimateState = null, start_hour: float = 8.0) -> void:
	climate = shared if shared != null else ClimateState.new()
	if climate.bio_time <= 0.0:
		climate.bio_time = clampf(start_hour, 0.0, 24.0) * Units.SECONDS_PER_HOUR
	_write_calendar(false)


func _process(delta: float) -> void:
	tick(delta)


## Advances by one real frame of `delta` seconds (respects pause and scale).
func tick(delta: float) -> void:
	if climate == null:
		setup()
	if paused or (is_inside_tree() and get_tree().paused):
		phys_dt = 0.0
		bio_dt = 0.0
		return
	phys_dt = clampf(delta, 0.0, MAX_REAL_DELTA) * time_scale
	bio_dt = phys_dt * Units.BIO_TIME_RATIO
	_advance_bio(bio_dt)


## Advances biological time directly (also works while paused).
func advance(bio_seconds: float) -> void:
	if climate == null:
		setup()
	_advance_bio(maxf(0.0, bio_seconds))


## Advances exactly one biological hour (the "step" button while paused).
func step_once() -> void:
	advance(Units.SECONDS_PER_HOUR)
	bio_dt = Units.SECONDS_PER_HOUR
	phys_dt = bio_dt / Units.BIO_TIME_RATIO


func set_scale_index(i: int) -> void:
	scale_index = clampi(i, 0, SCALES.size() - 1)
	time_scale = SCALES[scale_index]
	EventBus.time_scale_changed.emit(time_scale)


func faster() -> void:
	set_scale_index(scale_index + 1)


func slower() -> void:
	set_scale_index(scale_index - 1)


func set_paused(p: bool) -> void:
	if paused == p:
		return
	paused = p
	EventBus.time_scale_changed.emit(0.0 if paused else time_scale)


func toggle_pause() -> void:
	set_paused(not paused)


## Jumps the clock to a given hour of the current day (sandbox / previews).
func set_hour(h: float) -> void:
	if climate == null:
		setup()
	var day_start := floorf(climate.bio_time / Units.SECONDS_PER_DAY) * Units.SECONDS_PER_DAY
	climate.bio_time = day_start + clampf(h, 0.0, 23.999) * Units.SECONDS_PER_HOUR
	_write_calendar(false)


## Jumps to the start of a season (0..3) keeping the hour of day.
func set_season(s: int) -> void:
	if climate == null:
		setup()
	var hour_s := fmod(climate.bio_time, Units.SECONDS_PER_DAY)
	var year := floorf(climate.bio_time / (Units.SECONDS_PER_DAY * Units.DAYS_PER_YEAR))
	var day := year * Units.DAYS_PER_YEAR + clampi(s, 0, 3) * Units.DAYS_PER_SEASON
	climate.bio_time = day * Units.SECONDS_PER_DAY + hour_s
	_write_calendar(false)


func scale_label() -> String:
	if paused:
		return "Пауза"
	return "×%s" % (str(time_scale) if time_scale < 1.0 else str(int(time_scale)))


## Human-readable clock, e.g. "День 3, 14:05 · Лето".
func clock_label() -> String:
	if climate == null:
		return ""
	var h := int(climate.hour)
	var m := int((climate.hour - float(h)) * 60.0)
	return "День %d, %02d:%02d · %s" % [climate.day + 1, h, m, Units.SEASON_NAMES[climate.season]]


func _advance_bio(dt: float) -> void:
	climate.bio_time += dt
	_write_calendar(true)


func _write_calendar(emit: bool) -> void:
	var c := climate
	var total_hours := c.bio_time / Units.SECONDS_PER_HOUR
	c.day = int(floor(c.bio_time / Units.SECONDS_PER_DAY))
	c.hour = fmod(c.bio_time, Units.SECONDS_PER_DAY) / Units.SECONDS_PER_HOUR
	c.season = Units.season_of_day(c.day)
	var year_len := Units.SECONDS_PER_DAY * float(Units.DAYS_PER_YEAR)
	c.year_phase = fmod(c.bio_time, year_len) / year_len
	c.sun_direction = SunModel.direction(c.hour, c.year_phase, latitude)
	c.sun_elevation = rad_to_deg(asin(clampf(c.sun_direction.y, -1.0, 1.0)))
	c.daylight = SunModel.daylight(c.sun_elevation)
	var abs_hour := int(floor(total_hours))
	if not emit or _last_hour < 0:
		_last_hour = abs_hour
		_last_day = c.day
		_last_season = c.season
		return
	if abs_hour != _last_hour:
		var first := maxi(_last_hour + 1, abs_hour - MAX_HOUR_SIGNALS_PER_FRAME + 1)
		for hh in range(first, abs_hour + 1):
			EventBus.hour_changed.emit(hh % 24)
		_last_hour = abs_hour
	if c.day != _last_day:
		_last_day = c.day
		EventBus.day_changed.emit(c.day)
	if c.season != _last_season:
		_last_season = c.season
		EventBus.season_changed.emit(c.season)


func to_dict() -> Dictionary:
	return {
		"bio_time": climate.bio_time if climate != null else 0.0,
		"scale_index": scale_index, "paused": paused, "latitude": latitude,
	}


func from_dict(d: Dictionary) -> void:
	if climate == null:
		climate = ClimateState.new()
	climate.bio_time = maxf(0.0, Serial.f(d, "bio_time", 8.0 * Units.SECONDS_PER_HOUR))
	latitude = clampf(Serial.f(d, "latitude", 42.0), -80.0, 80.0)
	scale_index = clampi(Serial.i(d, "scale_index", DEFAULT_SCALE_INDEX), 0, SCALES.size() - 1)
	time_scale = SCALES[scale_index]
	paused = Serial.b(d, "paused", false)
	_last_hour = -1
	_write_calendar(false)
