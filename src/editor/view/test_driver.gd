class_name TestDriver
extends Node
## In-editor fallback "test" of a design: the creature walks, swims or flies a
## circle around the stage with a simple procedural animation, so the player
## sees what the anatomy can do even when the real test arena is unavailable.
## Purely visual (speeds come from the LocomotionProfile, scaled to the stage).

var active := false
var medium: StringName = &"land"
var _visual: CreatureVisual
var _ph: Phenotype
var _t := 0.0
var _speed_mps := 1.0


func set_phenotype(ph: Phenotype) -> void:
	_ph = ph


func attach(v: CreatureVisual, ph: Phenotype) -> void:
	_visual = v
	set_phenotype(ph)
	if not active:
		set_process(false)
	_apply(0.0)


## Chooses the medium that suits the design best.
static func best_medium(lp: LocomotionProfile) -> StringName:
	if lp.can_fly:
		return &"air"
	if lp.can_walk or lp.can_crawl:
		return &"land"
	if lp.can_swim:
		return &"water"
	return &"land"


func start(m: StringName = &"") -> void:
	if _ph == null:
		return
	medium = m if m != &"" else best_medium(_ph.locomotion)
	_speed_mps = clampf(maxf(_ph.locomotion.speed_in(medium), 0.1), 0.1, 40.0)
	active = true
	_t = 0.0
	set_process(true)


func stop() -> void:
	active = false
	set_process(false)
	if _visual != null:
		_visual.position = Vector3.ZERO
		_visual.rotation = Vector3.ZERO


func _process(delta: float) -> void:
	if _visual == null or not active:
		return
	_t += delta
	_apply(_t)


func _apply(t: float) -> void:
	if _visual == null or not active:
		return
	var radius := 1.7
	# Displayed speed: stage units per second, compressed so fast animals stay watchable.
	var sp := clampf(0.35 + 0.35 * log(1.0 + _speed_mps), 0.35, 2.0)
	var ang := t * sp / radius
	var pos := Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)
	var heading := Vector3(cos(ang), 0.0, -sin(ang))
	var yaw := atan2(-heading.x, -heading.z)
	match medium:
		&"air":
			pos.y = 0.9 + 0.12 * sin(t * 2.0)
		&"water":
			pos.y = 0.45 + 0.1 * sin(t * 1.3)
			yaw += 0.18 * sin(t * 4.0)
		_:
			pos.y = absf(sin(t * sp * 5.0)) * 0.03 if _ph.locomotion.can_walk else 0.0
			if not _ph.locomotion.can_walk:
				yaw += 0.12 * sin(t * 6.0)
	_visual.position = pos
	_visual.rotation = Vector3(0.0, yaw, 0.0)
	if medium == &"air":
		_visual.rotation.z = 0.12 * sin(t * 2.0)


