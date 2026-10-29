class_name RespirationModel
extends RefCounted
## Gas exchange derived from anatomy. Every respiratory organ has an O2
## supply capacity expressed as the aerobic metabolic power (W) it can
## support at full oxygen availability; demand is the current metabolic power.
##   * lungs     — ∝ lung volume; alveolar/parabronchial lungs of endotherms
##                 are ~5× more effective than simple sac lungs; fail when the
##                 animal has no access to air (breath-hold from the O2 store);
##   * gills     — ∝ gill area (size² × slits); collapse in air;
##   * trachea   — ∝ tracheal volume × diffusion efficiency that falls with
##                 body radius (why insects stay small);
##   * cutaneous — ∝ skin area × covering permeability; mucous skin needs
##                 moisture; works in water (tube feet count as skin there).
## Custom rule `ignore_oxygen` removes the requirement altogether.

const K_LUNG_SAC := 1.0e5          # W per m³ of simple (ectotherm) lung
const K_LUNG_ALVEOLAR := 3.0e5     # W per m³ of endotherm lung
const K_TRACHEA := 1.5e5           # W per m³ of tracheal system at efficiency 1
const TRACHEA_CRIT_RADIUS := 0.02  # m: body radius where tracheal efficiency halves
const K_GILL := 600.0              # W per m² of gill area (size² × slits)
const K_SKIN := 40.0               # W per m² of fully permeable moist skin
const SKIN_WATER_FACTOR := 0.8     # skin exchange in water vs moist air
const GILL_AIR_FACTOR := 0.04      # collapsed gill filaments in air
const TRACHEA_WATER_FACTOR := 0.03
const O2_DENSITY := 1.43           # kg/m³
const AIR_O2_FRACTION := 0.21
const LUNG_O2_USABLE := 0.6
const BLOOD_O2_J_PER_KG := 400.0   # metabolic J supported by blood/myoglobin O2 per kg body
const UNLIMITED := 1.0e9
## Gas permeability of coverings (0 impermeable .. 1 free diffusion).
const PERMEABILITY := {
	&"skin": 0.35, &"scales": 0.08, &"plates": 0.04, &"shell": 0.02, &"chitin": 0.04,
	&"fur": 0.05, &"feathers": 0.03, &"bristles": 0.05, &"slime": 1.0, &"membrane": 1.0,
}


static func build(p: PhysiologyProfile, ph: Phenotype) -> void:
	var m := ph.anatomy
	var st := m.stats
	var g := ph.genome
	var s := m.size_scale
	var organs: Dictionary = st.get("organ_volume", {})
	var eff := g.value(&"oxygen_efficiency")
	p.ignore_oxygen = bool(g.body_plan.rule("ignore_oxygen"))
	# Lungs.
	p.lung_volume = float(organs.get("lungs", 0.0))
	var k_lung := lerpf(K_LUNG_SAC, K_LUNG_ALVEOLAR, clampf(p.endothermy, 0.0, 1.0))
	p.lungs_w = p.lung_volume * k_lung * eff
	# Trachea: diffusion path ~ body radius of an equivalent cylinder.
	var trachea_vol := float(organs.get("trachea", 0.0))
	var length := maxf(float(st.get("length", 0.1)), 0.01)
	var body_r := sqrt(maxf(float(st.get("volume", 1e-6)), 1e-9) / (PI * length))
	p.body_radius = body_r
	p.trachea_efficiency = 1.0 / (1.0 + pow(body_r / TRACHEA_CRIT_RADIUS, 3.0)) if trachea_vol > 0.0 else 0.0
	p.trachea_w = trachea_vol * K_TRACHEA * p.trachea_efficiency * eff
	# Gills.
	var gill_area := 0.0
	for a in m.accessories:
		if a.type == &"gill":
			var part := g.body_plan.get_part(a.part_id)
			var slits := float(part.get_param("slits", 4)) if part != null else 4.0
			gill_area += pow(a.size * s, 2.0) * slits
	p.gill_area = gill_area
	p.gills_w = gill_area * K_GILL * eff
	# Skin: permeability of the covering on every body segment. Fins collapse
	# in air and wings are not respiratory surfaces; tube feet (sucker
	# tentacles) exchange gas in water.
	var perm_air := 0.0
	var perm_water := 0.0
	var moist_area := 0.0
	var total := 0.0
	var s2 := s * s
	for b in m.bones:
		if b.part_id < 0 or m.coverings.is_empty():
			continue
		var c := m.coverings[clampi(b.covering, 0, m.coverings.size() - 1)]
		var a_b := PI * (b.r0 + b.r1) * b.length * s2
		var perm := float(PERMEABILITY.get(c.type, 0.3)) / maxf(0.5, c.thickness)
		total += a_b
		if bool(c.props()["needs_moisture"]):
			moist_area += a_b
		if b.kind == &"wing":
			continue
		perm_water += a_b * perm
		if b.kind != &"fin":
			perm_air += a_b * perm
		if b.kind == &"tentacle":
			var part := g.body_plan.get_part(b.part_id)
			if part != null and bool(part.get_param("suckers", false)):
				perm_water += a_b * 0.8
	p.moist_skin_fraction = moist_area / total if total > 0.0 else 0.0
	p.skin_air_w = perm_air * K_SKIN * eff
	p.skin_water_w = perm_water * K_SKIN * SKIN_WATER_FACTOR * eff
	# O2 store: air in the lungs + blood/myoglobin.
	var lung_o2 := p.lung_volume * AIR_O2_FRACTION * O2_DENSITY * LUNG_O2_USABLE
	p.o2_store_j = lung_o2 / Units.O2_PER_JOULE + p.mass * BLOOD_O2_J_PER_KG
	_classify(p)


static func _classify(p: PhysiologyProfile) -> void:
	var contrib := {
		&"lungs": p.lungs_w, &"gills": p.gills_w, &"trachea": p.trachea_w,
		&"cutaneous": maxf(p.skin_air_w, p.skin_water_w),
	}
	var total := 0.0
	for k in contrib:
		total += float(contrib[k])
	if total <= p.bmr_watts * 0.05:
		p.respiration = &"none"
		return
	var best: StringName = &"cutaneous"
	var best_v := -1.0
	var significant := 0
	for k in contrib:
		var v := float(contrib[k])
		if v > best_v:
			best_v = v
			best = k
		if v >= 0.25 * total:
			significant += 1
	p.respiration = &"mixed" if significant >= 2 else best


## Aerobic power (W) the respiratory organs support in the given medium.
## mass_factor = current mass / adult mass (growth).
static func capacity(p: PhysiologyProfile, in_water: bool, oxygen: float, air_access: bool,
		humidity: float, mass_factor: float = 1.0) -> float:
	if p.ignore_oxygen:
		return UNLIMITED
	var cap := 0.0
	var air := (not in_water) or air_access
	if air:
		cap += p.lungs_w + p.trachea_w
	elif p.trachea_w > 0.0:
		cap += p.trachea_w * TRACHEA_WATER_FACTOR
	if in_water:
		cap += p.gills_w + p.skin_water_w
	else:
		cap += p.gills_w * GILL_AIR_FACTOR * (0.5 + humidity)
		# Mucous skin dries out in dry air.
		var moist := lerpf(1.0, clampf(humidity * 1.2, 0.15, 1.0), p.moist_skin_fraction)
		cap += p.skin_air_w * moist
	return cap * clampf(oxygen, 0.0, 1.5) * pow(maxf(mass_factor, 1e-4), 0.75)
