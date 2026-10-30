class_name QualityProfile
extends RefCounted
## Device-dependent budgets. PerformanceManager picks a level and adapts it at
## runtime; every system reads its budget from here instead of hardcoding.

const LEVELS: Array[StringName] = [&"low", &"medium", &"high"]

const PRESETS := {
	&"low": {
		"max_agents": 70, "max_tier_a": 8, "radius_a": 28.0, "radius_b": 70.0, "active_radius": 80.0,
		"ai_hz_a": 4.0, "ai_hz_b": 1.0, "anim_every_b": 4, "mesh_lod_bias": 1,
		"shadow_distance": 35.0, "shadows": false, "flora_density": 0.45, "flora_distance": 70.0,
		"terrain_lod_bias": 1, "particles": 0.35, "render_scale": 0.7, "fog_quality": 0,
	},
	&"medium": {
		"max_agents": 130, "max_tier_a": 14, "radius_a": 38.0, "radius_b": 95.0, "active_radius": 110.0,
		"ai_hz_a": 6.0, "ai_hz_b": 1.5, "anim_every_b": 3, "mesh_lod_bias": 0,
		"shadow_distance": 55.0, "shadows": true, "flora_density": 0.75, "flora_distance": 110.0,
		"terrain_lod_bias": 0, "particles": 0.7, "render_scale": 0.85, "fog_quality": 1,
	},
	&"high": {
		"max_agents": 220, "max_tier_a": 30, "radius_a": 50.0, "radius_b": 130.0, "active_radius": 150.0,
		"ai_hz_a": 8.0, "ai_hz_b": 2.0, "anim_every_b": 2, "mesh_lod_bias": 0,
		"shadow_distance": 80.0, "shadows": true, "flora_density": 1.0, "flora_distance": 160.0,
		"terrain_lod_bias": 0, "particles": 1.0, "render_scale": 1.0, "fog_quality": 2,
	},
}

var level: StringName = &"medium"
var values: Dictionary = PRESETS[&"medium"].duplicate()


func _init(lvl: StringName = &"medium") -> void:
	set_level(lvl)


func set_level(lvl: StringName) -> void:
	level = lvl if PRESETS.has(lvl) else &"medium"
	values = (PRESETS[level] as Dictionary).duplicate()


func get_value(key: String, fallback = null):
	return values.get(key, fallback)


func f(key: String) -> float:
	return float(values.get(key, 0.0))


func i(key: String) -> int:
	return int(values.get(key, 0))


## Guess a starting level from the platform before any measurement.
static func guess_level() -> StringName:
	var os := OS.get_name()
	var cores := OS.get_processor_count()
	if os in ["Android", "iOS"]:
		return &"medium" if cores >= 8 else &"low"
	if os == "Web":
		return &"low"
	return &"high" if cores >= 8 else &"medium"
