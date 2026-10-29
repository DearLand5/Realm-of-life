class_name MuscleSystem
extends RefCounted
## MuscleSystem: static analysis (groups from anatomy) + per-creature dynamic
## state (activation, fatigue, recovery, energy use).
##
## Usage (per creature):
##   var ms := MuscleSystem.new(phenotype)
##   ms.set_activation_by_function(&"walk", 0.6)   # from the locomotion controller
##   ms.update(phys_dt)                             # integrates fatigue
##   ms.available_force(&"walk")                    # 0..1 multiplier for speed/accel
##   ms.power_watts()                               # metabolic cost → BiologySystem
##   ms.bulge(group_index)                          # visual bulge for CreatureVisual

var groups: Array[MuscleGroup] = []
var activation := PackedFloat32Array()
var fatigue := PackedFloat32Array()
var _by_function: Dictionary = {}    # StringName -> PackedInt32Array
var _oxygen_factor: float = 1.0


func _init(ph: Phenotype = null) -> void:
	if ph != null:
		groups = analyze(ph.anatomy, ph.genome)
		_index()


## Builds muscle groups for every spine part instance that carries muscle.
static func analyze(model: AnatomyModel, genome: Genome) -> Array[MuscleGroup]:
	var out: Array[MuscleGroup] = []
	var plan := genome.body_plan
	var o2 := genome.value(&"oxygen_efficiency")
	var endo := genome.value(&"endothermy")
	for ii in model.instances.size():
		var inst := model.instances[ii]
		if inst.bones.is_empty():
			continue
		var mass := 0.0
		var length := 0.0
		var fast := 0.0
		for bi in inst.bones:
			var b := model.bones[bi]
			mass += b.muscle_mass
			length += b.length * model.size_scale
			fast += b.fast_twitch * b.muscle_mass
		if mass <= 1e-6:
			continue
		fast /= mass
		var g := MuscleGroup.new()
		g.index = out.size()
		g.instance = ii
		g.part_id = inst.part_id
		g.kind = inst.kind
		g.function = model.bones[inst.bones[0]].function
		g.side = inst.side
		g.bones = inst.bones.duplicate()
		g.mass = mass
		g.fast_twitch = fast
		var part := plan.get_part(inst.part_id)
		var base_name := part.label if part != null and part.label != "" else PartSchema.label(inst.kind)
		var side_txt := " (П)" if inst.side > 0 else (" (Л)" if inst.side < 0 else "")
		g.name = base_name + side_txt
		var cross_section := (mass / Units.TISSUE_DENSITY) / maxf(length, 0.005)
		g.max_force = cross_section * Units.MUSCLE_STRESS
		g.max_power = mass * Units.MUSCLE_POWER_PER_KG * (0.6 + 0.8 * fast) * (0.6 + 0.4 * endo)
		g.speed = 2.0 + 8.0 * fast
		g.endurance = clampf((1.0 - 0.7 * fast) * (0.7 + 0.3 * o2), 0.05, 1.0)
		g.energy_cost = g.max_power / MuscleGroup.EFFICIENCY
		g.recovery_rate = 0.02 + 0.08 * g.endurance * o2
		var stiff := 0.0
		for bi in inst.bones:
			stiff += model.bones[bi].stiffness
		g.working_range = clampf(0.9 - 0.4 * stiff / float(inst.bones.size()), 0.3, 0.95)
		out.append(g)
	return out


func _index() -> void:
	activation.resize(groups.size())
	fatigue.resize(groups.size())
	_by_function.clear()
	for g in groups:
		var key := g.function if g.function != &"none" else g.kind
		if not _by_function.has(key):
			_by_function[key] = PackedInt32Array()
		var arr: PackedInt32Array = _by_function[key]
		arr.append(g.index)
		_by_function[key] = arr


func group_indices(function_or_kind: StringName) -> PackedInt32Array:
	return _by_function.get(function_or_kind, PackedInt32Array())


func set_activation(i: int, a: float) -> void:
	if i >= 0 and i < activation.size():
		activation[i] = clampf(a, 0.0, 1.0)


func set_activation_by_function(function_or_kind: StringName, a: float) -> void:
	for i in group_indices(function_or_kind):
		activation[i] = clampf(a, 0.0, 1.0)


func relax_all() -> void:
	activation.fill(0.0)


## Oxygen / temperature limitation from physiology (0..1).
func set_oxygen_factor(f: float) -> void:
	_oxygen_factor = clampf(f, 0.05, 1.0)


## Integrates fatigue: exertion above the aerobic threshold builds fatigue,
## rest recovers it. dt = physical seconds.
func update(dt: float) -> void:
	for i in groups.size():
		var g := groups[i]
		var a := activation[i]
		var aerobic := g.endurance * 0.55 * _oxygen_factor
		var load := maxf(0.0, a - aerobic)
		fatigue[i] = clampf(fatigue[i] + load * (1.15 - g.endurance) * 0.35 * dt - g.recovery_rate * (1.0 - a) * dt, 0.0, 1.0)


## Force multiplier 0..1 for groups of a function (fatigued muscles are weaker).
func available_force(function_or_kind: StringName) -> float:
	var idx := group_indices(function_or_kind)
	if idx.is_empty():
		return 1.0
	var acc := 0.0
	for i in idx:
		acc += 1.0 - 0.75 * fatigue[i]
	return clampf(acc / float(idx.size()) * _oxygen_factor, 0.05, 1.0)


func mean_fatigue() -> float:
	if groups.is_empty():
		return 0.0
	var acc := 0.0
	var wsum := 0.0
	for i in groups.size():
		acc += fatigue[i] * groups[i].mass
		wsum += groups[i].mass
	return acc / maxf(wsum, 1e-9)


## Metabolic power currently spent by muscles (W).
func power_watts() -> float:
	var p := 0.0
	for i in groups.size():
		p += groups[i].energy_cost * activation[i]
	return p


## 0..1 visual bulge for a group (activation, slightly reduced by fatigue).
func bulge(i: int) -> float:
	return activation[i] * (1.0 - 0.4 * fatigue[i])


func total_force(function_or_kind: StringName) -> float:
	var f := 0.0
	for i in group_indices(function_or_kind):
		f += groups[i].max_force * (1.0 - 0.75 * fatigue[i])
	return f


func to_dict() -> Dictionary:
	return {"fatigue": Array(fatigue)}


func from_dict(d: Dictionary) -> void:
	var f: Array = Serial.arr(d, "fatigue")
	for i in mini(f.size(), fatigue.size()):
		fatigue[i] = clampf(float(f[i]), 0.0, 1.0)
