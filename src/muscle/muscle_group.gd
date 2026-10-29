class_name MuscleGroup
extends RefCounted
## Static description of one muscle group (one expanded part instance, e.g.
## "right hind leg"). Derived from AnatomyModel bone muscle masses.
##   max_force   — isometric force from physiological cross-section (N)
##   max_power   — mechanical power at full activation (W)
##   speed       — unloaded contraction speed (muscle lengths per second)
##   endurance   — 0..1, resistance to fatigue (slow fibres high)
##   energy_cost — metabolic cost at full activation (W, ~25 % efficiency)
##   working_range — fraction of joint range where force is effective

const EFFICIENCY := 0.25

var index: int = 0
var name: String = ""
var instance: int = -1
var part_id: int = -1
var kind: StringName = &""
var function: StringName = &"none"
var side: int = 0
var bones := PackedInt32Array()
var mass: float = 0.0
var max_force: float = 0.0
var max_power: float = 0.0
var speed: float = 4.0
var endurance: float = 0.5
var energy_cost: float = 0.0
var recovery_rate: float = 0.05     # fatigue recovered per physical second at rest
var working_range: float = 0.7
var fast_twitch: float = 0.5


func describe() -> Dictionary:
	return {
		"Сила сокращения": "%.0f Н" % max_force,
		"Мощность": "%.1f Вт" % max_power,
		"Скорость реакции": "%.1f дл/с" % speed,
		"Выносливость": "%d%%" % int(endurance * 100.0),
		"Энергозатраты": "%.1f Вт" % energy_cost,
	}
