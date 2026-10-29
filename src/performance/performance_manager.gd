class_name PerformanceManager
extends Node
## Distributes computation (ARCHITECTURE §7):
##   * assigns every live agent a simulation tier (A full / B simplified) and a
##     mesh LOD from distance to the focus and the per-quality budgets;
##   * decides which world sectors are "active" (individual agents) and which
##     stay statistical pools (tiers C/D) — with hysteresis so sectors don't
##     flicker between representations;
##   * switches the whole world to statistical mode at extreme time scales;
##   * adapts quality to the measured frame time (and to sustained slow-down,
##     the observable symptom of thermal throttling on phones).
##
## Agents are duck-typed: they need `global_position`, `set_tier(t)` and
## optionally `set_lod(l)`, `is_possessed()`.

signal quality_changed(level: StringName)
signal statistical_mode_changed(enabled: bool)

const STATISTICAL_SCALE := 256.0
const TARGET_FPS_MOBILE := 30.0
const TARGET_FPS_DESKTOP := 55.0
const ADAPT_WINDOW := 4.0          # s of sustained deviation before changing level
const SECTOR_HYSTERESIS := 1.25    # deactivate only beyond active_radius × this

var profile := QualityProfile.new()
var auto_quality := true
var statistical_mode := false
var focus := Vector3.ZERO
var sector_size: float = 32.0
var target_fps: float = TARGET_FPS_DESKTOP

var _fps_smooth: float = 60.0
var _low_time: float = 0.0
var _high_time: float = 0.0
var _baseline_frame_ms: float = -1.0
var _throttle_time: float = 0.0
var _active_sectors: Dictionary = {}   # Vector2i -> true
var _stats := {"tier_a": 0, "tier_b": 0, "agents": 0, "fps": 60.0}


func _ready() -> void:
	var os := OS.get_name()
	target_fps = TARGET_FPS_MOBILE if os in ["Android", "iOS"] else TARGET_FPS_DESKTOP
	apply_setting(str(Game.setting("quality")) if is_instance_valid(Game) else "auto")
	if is_instance_valid(Game):
		Game.register_service(&"performance", self)


func _exit_tree() -> void:
	if is_instance_valid(Game):
		Game.unregister_service(&"performance", self)


## "auto" | "low" | "medium" | "high"
func apply_setting(q: String) -> void:
	auto_quality = q == "auto" or not QualityProfile.PRESETS.has(StringName(q))
	set_level(QualityProfile.guess_level() if auto_quality else StringName(q))


func set_level(lvl: StringName) -> void:
	profile.set_level(lvl)
	_apply_render_settings()
	quality_changed.emit(profile.level)


func _apply_render_settings() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = profile.f("render_scale")
		vp.mesh_lod_threshold = 1.0 + float(profile.i("mesh_lod_bias")) * 2.0


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var fps := 1.0 / delta
	_fps_smooth = lerpf(_fps_smooth, fps, 0.05)
	_stats["fps"] = _fps_smooth
	if auto_quality:
		_adapt(delta)


func _adapt(delta: float) -> void:
	var idx := QualityProfile.LEVELS.find(profile.level)
	if _fps_smooth < target_fps * 0.85:
		_low_time += delta
		_high_time = 0.0
	elif _fps_smooth > target_fps * 1.35:
		_high_time += delta
		_low_time = 0.0
	else:
		_low_time = maxf(0.0, _low_time - delta)
		_high_time = maxf(0.0, _high_time - delta)
	# Thermal throttling heuristic: same load, frame time creeping up.
	var frame_ms := 1000.0 / maxf(_fps_smooth, 1.0)
	if _baseline_frame_ms < 0.0 and Engine.get_frames_drawn() > 300:
		_baseline_frame_ms = frame_ms
	if _baseline_frame_ms > 0.0 and frame_ms > _baseline_frame_ms * 1.35:
		_throttle_time += delta
	else:
		_throttle_time = maxf(0.0, _throttle_time - delta * 0.5)
	if (_low_time > ADAPT_WINDOW or _throttle_time > 30.0) and idx > 0:
		_low_time = 0.0
		_throttle_time = 0.0
		_baseline_frame_ms = -1.0
		set_level(QualityProfile.LEVELS[idx - 1])
		Game.notify("Качество графики снижено для плавности", &"info")
	elif _high_time > ADAPT_WINDOW * 3.0 and idx < QualityProfile.LEVELS.size() - 1 and idx < QualityProfile.LEVELS.find(QualityProfile.guess_level()) + 1:
		_high_time = 0.0
		set_level(QualityProfile.LEVELS[idx + 1])


# --- Simulation tiers ----------------------------------------------------------------

## Returns true when the world should be simulated purely statistically.
func update_time_scale(scale: float) -> bool:
	var stat := scale >= STATISTICAL_SCALE
	if stat != statistical_mode:
		statistical_mode = stat
		statistical_mode_changed.emit(stat)
	return statistical_mode


## Assigns tiers & LODs. Closest agents get tier A up to the budget.
func assign_tiers(agents: Array) -> void:
	var ra := profile.f("radius_a")
	var rb := profile.f("radius_b")
	var max_a := profile.i("max_tier_a")
	var scored := []
	for a in agents:
		if not is_instance_valid(a):
			continue
		var d := (a.global_position as Vector3).distance_to(focus)
		var possessed: bool = a.has_method("is_possessed") and a.is_possessed()
		scored.append([0.0 if possessed else d, a])
	scored.sort_custom(func(x, y): return x[0] < y[0])
	var n_a := 0
	var n_b := 0
	for entry in scored:
		var d: float = entry[0]
		var a = entry[1]
		var tier := 1
		if d < ra and n_a < max_a:
			tier = 0
			n_a += 1
		else:
			n_b += 1
		a.set_tier(tier)
		if a.has_method("set_lod"):
			var lod := 0 if d < ra * 0.6 else (1 if d < rb else 2)
			a.set_lod(mini(2, lod + profile.i("mesh_lod_bias")))
	_stats["tier_a"] = n_a
	_stats["tier_b"] = n_b
	_stats["agents"] = scored.size()


func sector_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / sector_size)), int(floor(p.z / sector_size)))


func sector_center(k: Vector2i) -> Vector3:
	return Vector3((float(k.x) + 0.5) * sector_size, 0.0, (float(k.y) + 0.5) * sector_size)


## Computes which sectors must hold individual agents. Returns
## {activate: Array[Vector2i], deactivate: Array[Vector2i]} relative to the
## previous call. In statistical mode every sector deactivates.
func update_active_sectors(world_half: float) -> Dictionary:
	var want := {}
	if not statistical_mode:
		var r := profile.f("active_radius")
		var k0 := sector_of(focus - Vector3(r, 0, r))
		var k1 := sector_of(focus + Vector3(r, 0, r))
		for z in range(k0.y, k1.y + 1):
			for x in range(k0.x, k1.x + 1):
				var k := Vector2i(x, z)
				var c := sector_center(k)
				if absf(c.x) > world_half + sector_size or absf(c.z) > world_half + sector_size:
					continue
				var d := Vector2(c.x - focus.x, c.z - focus.z).length()
				if d <= r or (_active_sectors.has(k) and d <= r * SECTOR_HYSTERESIS):
					want[k] = true
	var activate: Array[Vector2i] = []
	var deactivate: Array[Vector2i] = []
	for k in want:
		if not _active_sectors.has(k):
			activate.append(k)
	for k in _active_sectors:
		if not want.has(k):
			deactivate.append(k)
	_active_sectors = want
	return {"activate": activate, "deactivate": deactivate}


func is_sector_active(k: Vector2i) -> bool:
	return _active_sectors.has(k)


func active_sector_count() -> int:
	return _active_sectors.size()


func agent_budget() -> int:
	return profile.i("max_agents")


func stats() -> Dictionary:
	var s := _stats.duplicate()
	s["level"] = str(profile.level)
	s["active_sectors"] = _active_sectors.size()
	s["statistical"] = statistical_mode
	return s
