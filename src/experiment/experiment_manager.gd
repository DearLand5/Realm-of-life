class_name ExperimentManager
extends RefCounted
## Controlled experiment: from one snapshot of the world two copies are made —
## CONTROL (unchanged) and VARIANT (one parameter changed). Both are simulated
## with the same population model (tiers C/D) for N days, time-sliced so the
## live world keeps running, and their daily statistics are compared.
## The live world is never modified unless the player applies the change.

const VARIABLES := {
	&"temperature": {"label": "Температура, °C", "min": -15.0, "max": 15.0, "step": 0.5, "default": -6.0},
	&"moisture": {"label": "Влажность", "min": -0.5, "max": 0.5, "step": 0.05, "default": -0.25},
	&"resources": {"label": "Ресурсы растений, ×", "min": 0.2, "max": 3.0, "step": 0.1, "default": 0.5},
	&"mutation": {"label": "Частота мутаций, ×", "min": 0.0, "max": 6.0, "step": 0.25, "default": 4.0},
}
const STEP_DT := 6.0 * Units.SECONDS_PER_HOUR
const TRAITS: Array[StringName] = [&"size", &"fur_length", &"fat_reserve", &"endothermy", &"metabolism", &"thermal_optimum"]

var variable: StringName = &"temperature"
var value: float = -6.0
var days: int = 20
var control: SimState
var variant: SimState
var day_done: int = 0
var running := false
var finished := false
## results: {"days": PackedFloat32Array, "species": {id: {name, color, control: PackedFloat32Array, variant: PackedFloat32Array}},
##           "traits": {id: {trait: [control_end, variant_end]}}}
var results: Dictionary = {}
var _steps_left_in_day: int = 0
var _which: int = 0


func start(snapshot: Dictionary, var_id: StringName, v: float, n_days: int) -> void:
	variable = var_id
	value = v
	days = clampi(n_days, 1, 200)
	control = WorldBuilder.restore(snapshot)
	variant = WorldBuilder.restore(snapshot)
	# Live agents of the snapshot join the pools in both copies.
	for st: SimState in [control, variant]:
		var groups := {}
		for ind in st.saved_agents:
			var s := st.pop.sector_index((ind as Individual).position)
			if not groups.has(s):
				groups[s] = []
			(groups[s] as Array).append(ind)
		for s in groups:
			var list: Array[Individual] = []
			list.assign(groups[s])
			st.pop.fold(list, int(s))
		st.saved_agents.clear()
		st.pop.sector_budget = 0
		st.climate.bio_time = Serial.f(st.time_state, "bio_time", 0.0)
	apply_change(variant, variable, value)
	results = {"days": PackedFloat32Array(), "species": {}, "traits": {}}
	for d in control.evo.registry.alive():
		results["species"][d.id] = {"name": d.name, "color": d.ui_color, "control": PackedFloat32Array(), "variant": PackedFloat32Array()}
	_record()
	day_done = 0
	_steps_left_in_day = int(Units.SECONDS_PER_DAY / STEP_DT)
	_which = 0
	running = true
	finished = false


## Applies the experimental change to a SimState (also used to apply it to the live world).
static func apply_change(st: SimState, var_id: StringName, v: float) -> void:
	match var_id:
		&"temperature":
			st.climate.sandbox_temp_offset = v
		&"moisture":
			st.climate.sandbox_moisture_offset = v
		&"resources":
			st.climate.sandbox_resource_mult = v
		&"mutation":
			st.evo.set_mutation_rate(v)


static func describe(var_id: StringName, v: float) -> String:
	var spec: Dictionary = VARIABLES.get(var_id, {})
	return "%s = %s" % [spec.get("label", str(var_id)), str(snappedf(v, 0.01))]


func progress() -> float:
	return float(day_done) / float(days) if days > 0 else 1.0


## Advances the experiment within a time budget; returns true when finished.
func step(budget_ms: float = 6.0) -> bool:
	if not running:
		return finished
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < budget_ms:
		var st := control if _which == 0 else variant
		_advance(st, STEP_DT)
		_which = 1 - _which
		if _which == 0:
			_steps_left_in_day -= 1
			if _steps_left_in_day <= 0:
				day_done += 1
				_steps_left_in_day = int(Units.SECONDS_PER_DAY / STEP_DT)
				for s: SimState in [control, variant]:
					s.evo.daily(float(s.climate.day))
				_record()
				if day_done >= days:
					_finish()
					return true
	return false


func _advance(st: SimState, dt: float) -> void:
	st.climate.bio_time += dt
	var c := st.climate
	c.day = int(floor(c.bio_time / Units.SECONDS_PER_DAY))
	c.hour = fmod(c.bio_time, Units.SECONDS_PER_DAY) / Units.SECONDS_PER_HOUR
	var year := float(Units.DAYS_PER_YEAR) * Units.SECONDS_PER_DAY
	c.year_phase = fmod(c.bio_time, year) / year
	c.season = Units.season_of_day(c.day)
	st.eco.step_all(dt)
	st.pop.step(dt)


func _record() -> void:
	(results["days"] as PackedFloat32Array).append(float(day_done))
	for id in results["species"]:
		var e: Dictionary = results["species"][id]
		(e["control"] as PackedFloat32Array).append(control.evo.registry.count(int(id)))
		(e["variant"] as PackedFloat32Array).append(variant.evo.registry.count(int(id)))
	results["species"] = results["species"]


func _finish() -> void:
	running = false
	finished = true
	for id in results["species"]:
		var tc := control.pop.trait_means(int(id), TRAITS)
		var tv := variant.pop.trait_means(int(id), TRAITS)
		var td := {}
		for t in TRAITS:
			td[str(t)] = [float(tc.get(t, tc.get(str(t), 0.0))), float(tv.get(t, tv.get(str(t), 0.0)))]
		results["traits"][id] = td


func cancel() -> void:
	running = false
	control = null
	variant = null


## Short textual summary of the outcome.
func summary() -> String:
	if not finished:
		return ""
	var lines := PackedStringArray()
	lines.append("Эксперимент: %s, %d сут." % [describe(variable, value), days])
	for id in results["species"]:
		var e: Dictionary = results["species"][id]
		var c: PackedFloat32Array = e["control"]
		var v: PackedFloat32Array = e["variant"]
		var c_end := c[c.size() - 1]
		var v_end := v[v.size() - 1]
		var rel := (v_end - c_end) / maxf(1.0, c_end) * 100.0
		lines.append("«%s»: контроль %d, вариант %d (%+d%%)" % [e["name"], int(c_end), int(v_end), int(rel)])
	return "\n".join(lines)
