class_name WeatherModel
extends RefCounted
## Pure weather logic (no nodes): Markov transitions between weather states
## modulated by season and the observer region's climate, plus the target
## atmosphere of each state. Used by WeatherSystem and tests.

const STATES: Array[StringName] = [&"clear", &"cloudy", &"rain", &"storm", &"fog", &"snow"]
const LABELS := {
	&"clear": "Ясно", &"cloudy": "Облачно", &"rain": "Дождь",
	&"storm": "Гроза", &"fog": "Туман", &"snow": "Снег",
}
## Target atmosphere per state: cloud cover, precipitation, fog, wind m/s, temperature anomaly °C.
const TARGETS := {
	&"clear": {"cloud": 0.12, "precip": 0.0, "fog": 0.0, "wind": 2.5, "temp": 1.0},
	&"cloudy": {"cloud": 0.68, "precip": 0.0, "fog": 0.04, "wind": 4.0, "temp": -0.5},
	&"rain": {"cloud": 0.9, "precip": 0.6, "fog": 0.15, "wind": 5.5, "temp": -2.0},
	&"storm": {"cloud": 1.0, "precip": 1.0, "fog": 0.1, "wind": 11.0, "temp": -3.5},
	&"fog": {"cloud": 0.45, "precip": 0.0, "fog": 0.85, "wind": 0.8, "temp": -1.0},
	&"snow": {"cloud": 0.92, "precip": 0.55, "fog": 0.25, "wind": 4.5, "temp": -3.0},
}
## Base transition weights: from -> {to: weight}.
const BASE := {
	&"clear": {&"clear": 5.0, &"cloudy": 3.0, &"rain": 0.5, &"storm": 0.12, &"fog": 0.8, &"snow": 0.3},
	&"cloudy": {&"clear": 3.0, &"cloudy": 2.5, &"rain": 2.5, &"storm": 0.6, &"fog": 0.6, &"snow": 1.0},
	&"rain": {&"clear": 1.2, &"cloudy": 3.0, &"rain": 2.0, &"storm": 0.9, &"fog": 0.6, &"snow": 0.3},
	&"storm": {&"clear": 0.8, &"cloudy": 2.5, &"rain": 2.5, &"storm": 0.5, &"fog": 0.2, &"snow": 0.1},
	&"fog": {&"clear": 3.0, &"cloudy": 2.0, &"rain": 0.6, &"storm": 0.05, &"fog": 1.0, &"snow": 0.2},
	&"snow": {&"clear": 1.2, &"cloudy": 2.5, &"rain": 0.4, &"storm": 0.05, &"fog": 0.5, &"snow": 2.2},
}
## Typical duration range of each state, biological hours.
const DURATION := {
	&"clear": [6.0, 18.0], &"cloudy": [4.0, 12.0], &"rain": [2.0, 8.0],
	&"storm": [1.0, 3.0], &"fog": [2.0, 6.0], &"snow": [3.0, 10.0],
}


static func is_valid(s: StringName) -> bool:
	return s in STATES


static func label(s: StringName) -> String:
	return str(LABELS.get(s, "?"))


## Transition weights adjusted for season (0..3), regional temperature (°C)
## and humidity (0..1).
static func transition_weights(from: StringName, season: int, temp: float, moist: float) -> Dictionary:
	var base: Dictionary = BASE.get(from, BASE[&"clear"])
	var w := base.duplicate()
	var m := clampf(moist, 0.0, 1.0)
	var cold := clampf((1.5 - temp) / 4.0, 0.0, 1.0)      # precipitation falls as snow
	var hot := clampf((temp - 18.0) / 12.0, 0.0, 1.0)
	var wet := 0.35 + 1.5 * m
	var arid := 0.3 if m < 0.25 else 1.0
	w[&"clear"] = float(w[&"clear"]) * (1.6 - m)
	w[&"rain"] = float(w[&"rain"]) * wet * arid * (1.0 - cold)
	w[&"storm"] = float(w[&"storm"]) * wet * arid * (1.0 - cold) * (1.0 + 1.6 * hot) * [1.0, 1.6, 0.8, 0.15][clampi(season, 0, 3)]
	var snow_w := float(w[&"snow"]) + float(base[&"rain"]) * cold
	w[&"snow"] = snow_w * wet * arid * cold
	w[&"fog"] = float(w[&"fog"]) * (0.5 + m) * arid * [1.3, 0.6, 1.8, 1.0][clampi(season, 0, 3)] * (1.0 - hot * 0.7)
	return w


static func next_state(from: StringName, season: int, temp: float, moist: float, rng: Rng) -> StringName:
	var w := transition_weights(from if is_valid(from) else &"clear", season, temp, moist)
	var weights: Array = []
	for s in STATES:
		weights.append(maxf(0.0, float(w.get(s, 0.0))))
	var i := rng.weighted_index(weights)
	return STATES[i] if i >= 0 else &"clear"


static func duration_hours(s: StringName, rng: Rng) -> float:
	var r: Array = DURATION.get(s, [4.0, 8.0])
	return rng.range_f(float(r[0]), float(r[1]))


static func target(s: StringName) -> Dictionary:
	return TARGETS.get(s, TARGETS[&"clear"])
