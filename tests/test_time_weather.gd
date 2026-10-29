extends TestCase
## TimeController calendar math, sun model, weather Markov chain and the
## climate fields weather writes (headless; nodes are used without a tree).


func _clock(start_hour: float = 0.0) -> TimeController:
	var tc := TimeController.new()
	tc.setup(ClimateState.new(), start_hour, 0)
	return tc


func test_day_and_season_math() -> void:
	var tc := _clock(6.0)
	near(tc.climate.hour, 6.0, 1e-4, "starts at the requested hour")
	check(tc.climate.day == 0 and tc.climate.season == 0, "day 0, spring")
	tc.advance(24.0 * Units.SECONDS_PER_HOUR)
	check(tc.climate.day == 1, "24 bio hours = 1 day")
	near(tc.climate.hour, 6.0, 1e-3, "same hour next day")
	tc.advance(float(Units.DAYS_PER_SEASON - 1) * Units.SECONDS_PER_DAY)
	check(tc.climate.season == 1, "after 10 days → summer")
	tc.advance(float(Units.DAYS_PER_SEASON * 3) * Units.SECONDS_PER_DAY)
	check(tc.climate.season == 0 and tc.climate.day == Units.DAYS_PER_YEAR, "a year wraps to spring")
	near(tc.climate.year_phase, 6.0 / 24.0 / float(Units.DAYS_PER_YEAR), 1e-4, "year phase restarts")
	tc.free()


func test_scale_pause_and_step() -> void:
	var tc := _clock(10.0)
	tc.set_scale_index(4)   # ×4
	near(tc.time_scale, 4.0, 1e-6, "scale index 4 = ×4")
	tc.tick(0.05)
	near(tc.phys_dt, 0.2, 1e-6, "phys_dt = delta × scale")
	near(tc.bio_dt, 0.2 * Units.BIO_TIME_RATIO, 1e-4, "bio_dt = phys_dt × 60")
	var before := tc.climate.bio_time
	tc.set_paused(true)
	tc.tick(0.05)
	check(tc.phys_dt == 0.0 and tc.bio_dt == 0.0 and tc.climate.bio_time == before, "pause stops time")
	tc.step_once()
	near(tc.climate.bio_time - before, Units.SECONDS_PER_HOUR, 1e-3, "step advances one bio hour while paused")
	tc.set_paused(false)
	tc.tick(10.0)
	near(tc.phys_dt, TimeController.MAX_REAL_DELTA * 4.0, 1e-6, "hitches are clamped")
	tc.set_scale_index(99)
	check(tc.time_scale == 4096.0, "scale index clamped to max")
	tc.set_scale_index(-5)
	check(tc.time_scale == 0.25, "scale index clamped to min")
	tc.free()


func test_time_signals() -> void:
	var tc := _clock(23.5)
	var hours: Array[int] = []
	var days: Array[int] = []
	var on_hour := func(h: int) -> void: hours.append(h)
	var on_day := func(d: int) -> void: days.append(d)
	EventBus.hour_changed.connect(on_hour)
	EventBus.day_changed.connect(on_day)
	tc.advance(Units.SECONDS_PER_HOUR)          # 23:30 → 00:30
	tc.advance(3.0 * Units.SECONDS_PER_HOUR)    # → 03:30
	EventBus.hour_changed.disconnect(on_hour)
	EventBus.day_changed.disconnect(on_day)
	check(hours == [0, 1, 2, 3], "hour_changed for every crossed hour (%s)" % str(hours))
	check(days == [1], "day_changed once")
	tc.free()


func test_time_serialization() -> void:
	var tc := _clock(13.25)
	tc.set_scale_index(6)
	tc.advance(5.0 * Units.SECONDS_PER_DAY)
	var d := tc.to_dict()
	var tc2 := TimeController.new()
	tc2.from_dict(JSON.parse_string(JSON.stringify(d)))
	near(tc2.climate.bio_time, tc.climate.bio_time, 1e-2, "bio time restored")
	check(tc2.time_scale == tc.time_scale and tc2.climate.day == tc.climate.day, "scale and day restored")
	tc2.from_dict({"scale_index": "bad", "bio_time": -50})
	check(tc2.climate.bio_time >= 0.0 and tc2.time_scale == 1.0, "tolerates bad values")
	tc.free()
	tc2.free()


func test_sun_model() -> void:
	var noon := SunModel.elevation(12.0, 0.25, 42.0)
	var morning := SunModel.elevation(8.0, 0.25, 42.0)
	var midnight := SunModel.elevation(0.0, 0.25, 42.0)
	check(noon > morning and morning > 0.0 and midnight < 0.0, "noon > morning > 0 > midnight")
	near(noon, 90.0 - 42.0 + SunModel.AXIAL_TILT, 0.5, "summer solstice noon elevation")
	check(SunModel.elevation(12.0, 0.75, 42.0) < SunModel.elevation(12.0, 0.0, 42.0), "winter sun lower than equinox")
	var dir := SunModel.direction(12.0, 0.0, 42.0)
	check(dir.z > 0.5, "noon sun stands in the south (+Z) at northern latitude")
	check(SunModel.direction(7.0, 0.0, 42.0).x > 0.0, "morning sun in the east")
	var h := SunModel.hour_for_elevation(5.0, 0.25, 42.0, false)
	near(SunModel.elevation(h, 0.25, 42.0), 5.0, 0.05, "evening hour for 5° elevation")
	near(SunModel.daylight(30.0), 1.0, 1e-6, "full daylight")
	near(SunModel.daylight(-20.0), 0.0, 1e-6, "night")


func test_weather_transitions_valid() -> void:
	var rng := Rng.new(1234)
	var seen := {}
	var s: StringName = &"clear"
	for k in 4000:
		var season := k % 4
		var temp := rng.range_f(-25.0, 40.0)
		var moist := rng.randf()
		s = WeatherModel.next_state(s, season, temp, moist, rng)
		if not WeatherModel.is_valid(s):
			check(false, "state valid: %s" % s)
		seen[s] = true
		var d := WeatherModel.duration_hours(s, rng)
		if d <= 0.0:
			check(false, "positive duration")
	check(seen.size() == WeatherModel.STATES.size(), "all states reachable (%s)" % str(seen.keys()))
	check(WeatherModel.next_state(&"nonsense", 0, 10.0, 0.5, rng) in WeatherModel.STATES, "unknown state recovers")
	# Climate shapes the chain: no snow in the heat, no rain in deep frost.
	var hot := WeatherModel.transition_weights(&"cloudy", 1, 30.0, 0.7)
	check(float(hot[&"snow"]) == 0.0, "no snow at 30 °C")
	var frost := WeatherModel.transition_weights(&"cloudy", 3, -15.0, 0.7)
	check(float(frost[&"rain"]) == 0.0 and float(frost[&"snow"]) > 0.0, "frost turns rain into snow")
	var desert := WeatherModel.transition_weights(&"clear", 1, 28.0, 0.1)
	var jungle := WeatherModel.transition_weights(&"clear", 1, 28.0, 0.9)
	check(float(desert[&"rain"]) < float(jungle[&"rain"]), "dry regions rain less")
	for st in WeatherModel.STATES:
		check(WeatherModel.label(st) != "?", "Russian label for %s" % st)


func _weather_world(temp_offset: float, moist_offset: float) -> WeatherSystem:
	var w := WorldGenerator.generate({"seed": 3, "size": 256.0, "resolution": 65, "temperature_offset": temp_offset, "moisture_offset": moist_offset})
	var c := ClimateState.new()
	c.world = w
	var tc := TimeController.new()
	tc.setup(c, 8.0)
	var ws := WeatherSystem.new()
	ws.visuals_enabled = false
	ws.setup(c, w, tc, null, 77)
	ws.set_meta("clock", tc)
	return ws


func _free_ws(ws: WeatherSystem) -> void:
	var tc: TimeController = ws.get_meta("clock")
	tc.free()
	ws.free()


func test_weather_writes_sane_climate() -> void:
	var ws := _weather_world(0.0, 0.0)
	var c := ws.climate
	var tc: TimeController = ws.get_meta("clock")
	var states := {}
	var ok := true
	var p := Vector3(0, c.world.height_at(0, 0) + 1.0, 0)
	for k in 24 * 60:    # 60 days in 1-hour steps
		tc.advance(Units.SECONDS_PER_HOUR)
		ws.advance(Units.SECONDS_PER_HOUR)
		ws._update_gusts()
		states[c.weather] = true
		ok = ok and WeatherModel.is_valid(c.weather)
		for v in [c.cloud_cover, c.precipitation, c.fog, c.drought, c.snow_cover, c.wetness]:
			ok = ok and v >= 0.0 and v <= 1.0 and not is_nan(v)
		var t := c.temperature_at(p)
		ok = ok and t > -60.0 and t < 60.0 and c.wind.length() < 40.0
		ok = ok and c.humidity_at(p) >= 0.0 and c.humidity_at(p) <= 1.0
	check(ok, "weather fields and temperatures stay in range")
	check(states.size() >= 3, "weather changes over two months (%s)" % str(states.keys()))
	_free_ws(ws)


func test_drought_and_snow_respond_to_climate() -> void:
	# Hot and dry: forced clear weather → drought builds up.
	var hot := _weather_world(14.0, -0.4)
	hot.force_weather(&"clear", true, 1.0e6)
	hot.climate.year_phase = 0.375
	for k in 24 * 12:
		hot.advance(Units.SECONDS_PER_HOUR)
	check(hot.climate.drought > 0.3, "drought accumulates in heat without rain (%.2f)" % hot.climate.drought)
	hot.force_weather(&"rain", true, 1.0e6)
	var before := hot.climate.drought
	for k in 24:
		hot.advance(Units.SECONDS_PER_HOUR)
	check(hot.climate.drought < before and hot.climate.wetness > 0.3, "rain relieves drought and wets the ground")
	_free_ws(hot)
	# Cold: forced snowfall → snow cover builds, then melts in a thaw.
	var cold := _weather_world(-25.0, 0.2)
	cold.force_weather(&"snow", true, 1.0e6)
	for k in 24:
		cold.advance(Units.SECONDS_PER_HOUR)
	check(cold.climate.snow_cover > 0.5, "snow cover builds below 0 °C (%.2f)" % cold.climate.snow_cover)
	check(cold.climate.weather == &"snow", "precipitation stays snow in frost")
	var p := Vector3(0, cold.world.height_at(0, 0), 0)
	check(cold.climate.snow_at(p) > 0.3, "ClimateState.snow_at reports lying snow")
	cold.climate.sandbox_temp_offset = 40.0
	cold.force_weather(&"clear", true, 1.0e6)
	for k in 24 * 3:
		cold.advance(Units.SECONDS_PER_HOUR)
	check(cold.climate.snow_cover < 0.1, "snow melts in a thaw (%.2f)" % cold.climate.snow_cover)
	_free_ws(cold)


func test_weather_serialization() -> void:
	var ws := _weather_world(0.0, 0.0)
	ws.force_weather(&"storm", true, 3.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(ws.to_dict()))
	var ws2 := _weather_world(0.0, 0.0)
	ws2.from_dict(d)
	check(ws2.state == &"storm" and ws2.climate.weather == &"storm", "weather state restored")
	ws2.from_dict({"state": "blizzard??"})
	check(ws2.state == &"clear", "unknown state falls back to clear")
	var c := ClimateState.new()
	c.snow_cover = 0.4
	c.wetness = 0.7
	var c2 := ClimateState.new()
	c2.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	near(c2.snow_cover, 0.4, 1e-4, "snow cover saved")
	near(c2.wetness, 0.7, 1e-4, "wetness saved")
	_free_ws(ws)
	_free_ws(ws2)
