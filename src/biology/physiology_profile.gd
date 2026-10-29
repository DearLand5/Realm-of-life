class_name PhysiologyProfile
extends RefCounted
## Physiological capabilities of a phenotype (rates in REAL units, time in
## BIOLOGICAL seconds — see Units). Owned by BiologySystem.
##
## CONTRACT (stable API used by other systems):
##   static build(ph: Phenotype) -> PhysiologyProfile
##   bmr_watts, max_energy, respiration, habitat_ok, diet_eff, lifespan,
##   maturity_age, diagnose() -> Array[Dictionary]{level, system, text}
## This file starts as a compact baseline; BiologySystem extends it.

var bmr_watts: float = 1.0            # basal metabolic rate (W) at thermal optimum
var max_energy: float = 1.0e5         # J storable (fat + glycogen)
var respiration: StringName = &"cutaneous"   # lungs | gills | trachea | cutaneous | mixed | none
var habitat_ok := {"land": true, "water": false}
var diet_eff := {"plant": 0.5, "meat": 0.3, "carrion": 0.1, "filter": 0.0, "photo": 0.0}
var lifespan: float = 20.0 * Units.SECONDS_PER_DAY
var maturity_age: float = 4.0 * Units.SECONDS_PER_DAY
var endothermy: float = 0.5
var notes: Array[Dictionary] = []


static func build(ph: Phenotype) -> PhysiologyProfile:
	var p := PhysiologyProfile.new()
	var g := ph.genome
	var st := ph.anatomy.stats
	var m := maxf(float(st.get("mass", 1.0)), 1e-4)
	p.endothermy = g.value(&"endothermy")
	var factor := lerpf(Units.ECTOTHERM_FACTOR, 1.0, p.endothermy)
	p.bmr_watts = Units.KLEIBER_COEF * pow(m, 0.75) * g.value(&"metabolism") * factor
	p.max_energy = (float(st.get("fat_mass", m * 0.08)) + m * 0.02) * Units.FAT_ENERGY
	var organs: Dictionary = st.get("organ_volume", {})
	var kinds: Dictionary = st.get("kind_count", {})
	var has_lungs := organs.has("lungs")
	var has_gills := int(kinds.get(&"gill", 0)) > 0
	var has_trachea := organs.has("trachea")
	if has_lungs and has_gills:
		p.respiration = &"mixed"
	elif has_lungs:
		p.respiration = &"lungs"
	elif has_gills:
		p.respiration = &"gills"
	elif has_trachea:
		p.respiration = &"trachea"
	else:
		p.respiration = &"cutaneous"
	p.habitat_ok = {"land": p.respiration != &"gills", "water": p.respiration in [&"gills", &"mixed", &"cutaneous"]}
	p.diet_eff = {
		"plant": g.value(&"digestion_plant"), "meat": g.value(&"digestion_meat"),
		"carrion": g.value(&"digestion_carrion"), "filter": 0.0, "photo": g.value(&"photosynthesis"),
	}
	# Lifespan scales ~ M^0.2 (allometry), in game days.
	p.lifespan = (8.0 + 10.0 * pow(m, 0.2)) * g.value(&"lifespan") * Units.SECONDS_PER_DAY
	p.maturity_age = p.lifespan * 0.18 * g.value(&"maturity_age")
	return p


func diagnose() -> Array[Dictionary]:
	return notes.duplicate()
