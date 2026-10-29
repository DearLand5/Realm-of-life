class_name LocomotionProfile
extends RefCounted
## What a body can physically do, derived from anatomy (no animation tricks).
## Simplified but causal biomechanics (all real units):
##   * walking/running — Froude scaling with leg length, limited by muscle
##     power-to-weight and by bone stress under body weight;
##   * crawling/undulation — body length, segmentation and flexibility;
##   * swimming — thrust power vs. quadratic drag of the frontal area;
##   * flight — lift L = ½ρv²S·CL against weight, power required vs. power
##     of the flight muscles; wing loading limits;
##   * jumping — specific muscle work of leg muscles (size independent, as in
##     Borelli's law);
##   * climbing — grasping/clinging organs and an adhesion size limit.
## `notes` explain limiting factors (shown by anatomical diagnostics).

const LOCOMOTOR_FUNCTIONS: Array[StringName] = [&"walk", &"run", &"climb", &"swim", &"fly", &"dig"]
const MUSCLE_SPECIFIC_WORK := 60.0     # J/kg per contraction (jump)
const FLIGHT_MUSCLE_POWER := 210.0     # W/kg sustained flight muscle
const CL_MAX := {"membrane": 1.4, "feather": 1.6, "insect": 3.0}
const MAX_WING_LOADING := 260.0        # N/m^2, heavier birds rarely exceed this
const CLIMB_MASS_LIMIT := 180.0        # kg

var mass: float = 1.0
var stance: StringName = &"none"   # biped quadruped hexapod multiped monopod apod radial
var gait: StringName = &"none"     # legged serpentine peristaltic tentacle flagellar none
var can_walk := false
var can_crawl := false
var can_swim := false
var can_fly := false
var can_glide := false
var can_hover := false
var can_climb := false
var can_jump := false
var can_burrow := false
var walk_speed: float = 0.0
var run_speed: float = 0.0
var crawl_speed: float = 0.0
var swim_speed: float = 0.0
var fly_speed: float = 0.0
var climb_speed: float = 0.0
var jump_height: float = 0.0
var takeoff_speed: float = 0.0
var wing_loading: float = 0.0
var flight_power_required: float = 0.0
var flight_power_available: float = 0.0
var locomotor_power: float = 0.0   # W
var max_force: float = 0.0         # N
var accel: float = 1.0             # m/s^2
var turn_rate: float = 2.0         # rad/s
var agility: float = 0.5           # 0..1
var stability: float = 0.5         # 0..1
var support_ratio: float = 0.0     # bone stress / safe limit (>1 = overloaded)
var buoyancy: float = 0.0          # -1 sinks fast .. +1 floats
var leg_length: float = 0.0
var stride_length: float = 0.0
var cost_walk: float = 0.0         # J per metre
var cost_swim: float = 0.0
var cost_fly: float = 0.0
var cost_crawl: float = 0.0
var notes: Array[Dictionary] = []  # {level, text}


func best_land_speed() -> float:
	return maxf(run_speed if can_walk else 0.0, crawl_speed if can_crawl else 0.0)


func land_cost_per_m() -> float:
	return cost_walk if can_walk else cost_crawl


## Max speed in a medium: &"land", &"water", &"air".
func speed_in(medium: StringName) -> float:
	match medium:
		&"water":
			return swim_speed if can_swim else 0.0
		&"air":
			return fly_speed if can_fly else 0.0
	return best_land_speed()


func habitat_scores() -> Dictionary:
	return {
		"land": clampf(best_land_speed() / 2.0, 0.0, 1.0),
		"water": clampf(swim_speed / 2.0, 0.0, 1.0) if can_swim else 0.0,
		"air": 1.0 if can_fly else (0.3 if can_glide else 0.0),
	}


func _note(level: StringName, text: String) -> void:
	notes.append({"level": level, "text": text})


static func build(model: AnatomyModel, genome: Genome) -> LocomotionProfile:
	var lp := LocomotionProfile.new()
	var st := model.stats
	var plan := genome.body_plan
	var s := model.size_scale
	var m := maxf(float(st.get("mass", 1.0)), 1e-4)
	lp.mass = m
	var g := Units.GRAVITY
	var ignore_support := bool(plan.rule("ignore_support"))

	# --- Muscle groups -------------------------------------------------------------
	var leg_muscle := 0.0
	var leg_fast := 0.0
	var swim_muscle := 0.0
	var wing_muscle := 0.0
	var axial_muscle := 0.0
	var axial_segments := 0
	var tentacle_count := 0
	var tentacle_len := 0.0
	var flagella := 0
	var webbed := 0
	var climbers := 0
	var diggers := 0
	for b in model.bones:
		if b.part_id < 0:
			continue
		match b.kind:
			&"torso", &"tail", &"cell":
				axial_muscle += b.muscle_mass
				if b.kind != &"cell":
					axial_segments += 1
			&"wing":
				wing_muscle += b.muscle_mass
			&"fin":
				swim_muscle += b.muscle_mass
			&"tentacle":
				swim_muscle += b.muscle_mass * 0.5
			&"limb":
				if b.function in [&"walk", &"run", &"climb", &"dig"]:
					leg_muscle += b.muscle_mass
					leg_fast += b.muscle_mass * b.fast_twitch
				elif b.function == &"swim":
					swim_muscle += b.muscle_mass
				elif b.function == &"fly":
					wing_muscle += b.muscle_mass
	for inst in model.instances:
		var part := plan.get_part(inst.part_id)
		if part == null:
			continue
		match part.kind:
			&"tentacle":
				tentacle_count += 1
				tentacle_len += part.total_length() * s
			&"flagellum":
				flagella += 1
			&"limb":
				var foot := str(part.get_param("foot", "pad"))
				if foot == "web":
					webbed += 1
				if part.function == &"climb" or part.function == &"grasp" or foot in ["claw", "sucker", "hand"]:
					climbers += 1
				if part.function == &"dig":
					diggers += 1
	if tentacle_count > 0:
		tentacle_len /= float(tentacle_count)
	var fast := leg_fast / maxf(leg_muscle, 1e-9) if leg_muscle > 0.0 else 0.5
	# Ectotherm muscles deliver less sustained power (temperature-limited).
	var power_k := 0.6 + 0.4 * genome.value(&"endothermy")
	lp.locomotor_power = (leg_muscle + swim_muscle + wing_muscle + axial_muscle * 0.5) * Units.MUSCLE_POWER_PER_KG * power_k

	# --- Legged locomotion -------------------------------------------------------------
	var n_sup := int(st.get("support_count", 0))
	lp.leg_length = float(st.get("leg_length", 0.0))
	lp.support_ratio = 0.0 if ignore_support else float(st.get("bone_stress", 0.0)) / Units.BONE_STRESS_LIMIT
	match n_sup:
		0:
			lp.stance = &"apod"
		1:
			lp.stance = &"monopod"
		2:
			lp.stance = &"biped"
		3, 4:
			lp.stance = &"quadruped"
		5, 6:
			lp.stance = &"hexapod"
		_:
			lp.stance = &"multiped"
	if plan.body_axis == &"vertical" and n_sup == 0 and tentacle_count >= 3:
		lp.stance = &"radial"
	var leg_power := leg_muscle * Units.MUSCLE_POWER_PER_KG * (0.6 + 0.8 * fast) * power_k
	if n_sup > 0 and lp.leg_length > 0.005:
		var p2w := leg_power / (m * g)  # m/s
		var run_factor := clampf(p2w / 3.0, 0.15, 1.6)
		var fr_max := 0.5 + 2.6 * run_factor
		if n_sup >= 6:
			fr_max = minf(fr_max, 2.2)
		var feet_bonus := 1.0
		for a in model.accessories_of_type(&"foot"):
			match str(a.params.get("foot", "pad")):
				"hoof":
					feet_bonus += 0.08 / float(n_sup)
				"pad", "claw":
					feet_bonus += 0.03 / float(n_sup)
				"sucker", "web":
					feet_bonus -= 0.05 / float(n_sup)
		var runners := int((st.get("function_count", {}) as Dictionary).get(&"run", 0))
		if runners > 0:
			fr_max *= 1.15
		var L := lp.leg_length
		lp.walk_speed = sqrt(0.35 * g * L) * feet_bonus
		lp.run_speed = maxf(lp.walk_speed, sqrt(fr_max * g * L) * feet_bonus)
		lp.stride_length = L * 1.2
		lp.can_walk = true
		if lp.support_ratio > 1.0:
			var k := clampf(1.0 / (lp.support_ratio * lp.support_ratio), 0.05, 1.0)
			lp.walk_speed *= k
			lp.run_speed *= k * k
			lp._note(&"critical" if lp.support_ratio > 2.5 else &"warning",
				"Конечности перегружены: напряжение костей %d%% от безопасного предела. Утолщите ноги, добавьте опоры или уменьшите массу." % int(lp.support_ratio * 100.0))
		elif lp.support_ratio > 0.75:
			lp._note(&"info", "Опорная система работает близко к пределу (%d%%)." % int(lp.support_ratio * 100.0))
		match lp.stance:
			&"biped":
				lp.stability = 0.55
			&"monopod":
				lp.stability = 0.3
				lp.run_speed *= 0.7
				lp._note(&"warning", "Одна опорная конечность: только прыжковое передвижение, низкая устойчивость.")
			&"quadruped":
				lp.stability = 0.85 if n_sup == 4 else 0.7
			_:
				lp.stability = 0.95
		var com_h := float(st.get("height", 1.0)) * 0.6
		var width := float(st.get("width", 0.5))
		lp.stability = clampf(lp.stability * clampf(width / maxf(com_h, 0.01) + 0.4, 0.3, 1.2), 0.05, 1.0)
		lp.gait = &"legged"
	# --- Crawling / undulation (also fallback for overloaded legs) ----------------------
	var body_len := float(st.get("length", 0.5))
	var flex := float(st.get("flexibility", 0.8))
	var seg_factor := clampf(float(axial_segments) / 6.0, 0.15, 1.0)
	lp.crawl_speed = 0.25 * sqrt(g * body_len) * seg_factor * flex * clampf(axial_muscle * 4.0 / m, 0.2, 1.2)
	if tentacle_count >= 3:
		lp.crawl_speed = maxf(lp.crawl_speed, 0.22 * sqrt(g * maxf(tentacle_len, 0.01)))
	lp.can_crawl = lp.crawl_speed > 0.01
	# Lateral (serpentine) undulation needs anisotropic friction from scales;
	# smooth/slimy bodies crawl by slower peristalsis.
	var scaly := false
	for cov in model.coverings:
		if cov.type in [&"scales", &"plates", &"chitin"]:
			scaly = true
	if tentacle_count < 3 and not scaly:
		lp.crawl_speed *= 0.3
	if not lp.can_walk:
		if tentacle_count >= 3:
			lp.gait = &"tentacle"
		elif flagella > 0:
			lp.gait = &"flagellar"
		elif axial_segments >= 4 and scaly and flex > 0.6:
			lp.gait = &"serpentine"
		else:
			lp.gait = &"peristaltic"
	# --- Jumping ------------------------------------------------------------------------
	if n_sup > 0:
		lp.jump_height = leg_muscle * MUSCLE_SPECIFIC_WORK * (0.4 + 0.9 * fast) / (m * g)
		if lp.support_ratio > 1.0:
			lp.jump_height /= lp.support_ratio
		lp.can_jump = lp.jump_height > 0.04 * maxf(float(st.get("height", 0.5)), 0.05)
	# --- Climbing / burrowing --------------------------------------------------------------
	var suckers := tentacle_count > 0 and plan.parts_of_kind(&"tentacle").any(func(p): return bool(p.get_param("suckers", false)))
	if (climbers >= 2 or suckers) and m < CLIMB_MASS_LIMIT:
		lp.can_climb = true
		lp.climb_speed = maxf(lp.walk_speed, lp.crawl_speed) * 0.45 * clampf(1.0 - m / CLIMB_MASS_LIMIT, 0.2, 1.0)
	elif climbers >= 2:
		lp._note(&"info", "Слишком тяжёлое тело для лазания (масса > %d кг)." % int(CLIMB_MASS_LIMIT))
	lp.can_burrow = diggers >= 2 or (axial_segments >= 6 and float(st.get("streamline", 1.0)) > 4.0)

	# --- Swimming ------------------------------------------------------------------------
	var w := float(st.get("width", 0.3))
	var h := float(st.get("height", 0.3))
	var frontal := PI * maxf(w, 0.005) * 0.5 * maxf(h, 0.005) * 0.5
	var streamline := float(st.get("streamline", 2.0))
	var cd := clampf(0.04 + 0.35 / maxf(streamline, 0.3), 0.05, 1.2)
	var fin_area := float(st.get("fin_area", 0.0))
	var web_area := 0.0
	if webbed > 0:
		for a in model.accessories_of_type(&"foot"):
			if str(a.params.get("foot", "")) == "web":
				web_area += pow(a.size * s * 3.0, 2.0)
	var finned := fin_area > 0.0 or web_area > 0.0
	var undulation_area := body_len * h * 0.3 * flex * seg_factor * (1.0 if (finned or n_sup == 0) else 0.15)
	var prop_area := fin_area + web_area + undulation_area + float(tentacle_count) * 0.02 * tentacle_len * tentacle_len
	var swim_power := (swim_muscle + axial_muscle * 0.7 + leg_muscle * 0.25) * Units.MUSCLE_POWER_PER_KG * power_k
	if flagella > 0:
		swim_power += m * 2.0 * float(flagella)
		prop_area += float(flagella) * body_len * body_len * 0.05
	var eff := 0.08 + 0.7 * prop_area / (prop_area + frontal * 2.0)
	if swim_power > 0.0:
		lp.swim_speed = pow(2.0 * swim_power * eff / (Units.WATER_DENSITY * cd * frontal), 1.0 / 3.0)
		# Burst speeds rarely exceed ~3 body lengths per second.
		lp.swim_speed = minf(lp.swim_speed, 0.3 + 3.0 * body_len)
	lp.can_swim = lp.swim_speed > 0.15
	var vol := maxf(float(st.get("volume", 0.001)), 1e-9)
	var organs: Dictionary = st.get("organ_volume", {})
	var gas := float(organs.get("lungs", 0.0)) + float(organs.get("swim_bladder", 0.0)) * 1.5
	var density := m / (vol + gas)
	lp.buoyancy = clampf((Units.WATER_DENSITY - density) / 150.0, -1.0, 1.0)
	if organs.has("swim_bladder"):
		lp.buoyancy = clampf(lp.buoyancy * 0.2, -0.1, 0.1)

	# --- Flight --------------------------------------------------------------------------
	var wing_area := float(st.get("wing_area", 0.0))
	if wing_area > 0.0:
		lp.wing_loading = m * g / wing_area
		var span := 0.0
		var insect := false
		var cl := 1.4
		for a in model.accessories_of_type(&"membrane"):
			var part := plan.get_part(a.part_id)
			if part != null and part.kind == &"wing":
				span = maxf(span, part.total_length() * s * 2.0)
				var wt := str(part.get_param("wing_type", "membrane"))
				cl = maxf(cl, float(CL_MAX.get(wt, 1.4)))
				if wt == "insect":
					insect = true
		lp.takeoff_speed = sqrt(2.0 * m * g / (Units.AIR_DENSITY * wing_area * cl))
		var ar := span * span / wing_area
		var l_d := clampf(2.0 + 1.1 * ar, 3.0, 18.0)
		lp.flight_power_required = m * g * lp.takeoff_speed / l_d * 1.6
		# Flight muscles sit largely in the torso (pectoralis / thoracic muscles);
		# insect asynchronous flight muscle delivers ~1.5x the specific power.
		var flight_muscle := wing_muscle + axial_muscle * (0.6 if insect else 0.45)
		lp.flight_power_available = flight_muscle * FLIGHT_MUSCLE_POWER * (2.0 if insect else 1.0) * (0.6 + 0.3 * genome.value(&"metabolism")) * power_k
		var ratio := lp.flight_power_available / maxf(lp.flight_power_required, 1e-6)
		if lp.wing_loading <= MAX_WING_LOADING and ratio >= 1.0:
			lp.can_fly = true
			lp.fly_speed = lp.takeoff_speed * 1.5 * pow(clampf(ratio, 1.0, 3.0), 1.0 / 3.0)
			lp.can_hover = insect and m < 0.5 and ratio > 2.0
		else:
			if lp.wing_loading > MAX_WING_LOADING:
				lp._note(&"warning", "Недостаточная площадь крыльев: нагрузка %d Н/м² (предел ≈ %d). Увеличьте крылья или снизьте массу." % [int(lp.wing_loading), int(MAX_WING_LOADING)])
			if ratio < 1.0:
				lp._note(&"warning", "Мощности летательных мышц не хватает для полёта: нужно %.0f Вт, доступно %.0f Вт." % [lp.flight_power_required, lp.flight_power_available])
			lp.can_glide = lp.wing_loading < MAX_WING_LOADING * 2.5
			if lp.can_glide:
				lp._note(&"info", "Крылья позволяют планировать, но не летать активно.")
		lp.cost_fly = lp.flight_power_required / maxf(lp.fly_speed, 0.5)
	elif plan.parts_of_kind(&"wing").size() > 0:
		lp._note(&"warning", "Крылья без площади: увеличьте ширину крыла.")

	# --- Dynamics & energetic costs ----------------------------------------------------------
	lp.max_force = (leg_muscle + swim_muscle + wing_muscle + axial_muscle * 0.3) / Units.TISSUE_DENSITY / maxf(body_len * 0.3, 0.01) * Units.MUSCLE_STRESS
	lp.accel = clampf(lp.max_force / m, 0.5, 40.0)
	var p2w_all := lp.locomotor_power / (m * g)
	lp.agility = clampf(p2w_all / 4.0 / sqrt(maxf(body_len, 0.05)) * flex, 0.05, 1.0)
	lp.turn_rate = 0.8 + 5.0 * lp.agility
	var armor_mass := float(st.get("covering_mass", 0.0)) + float(st.get("hard_mass", 0.0))
	var load := 1.0 + 0.8 * armor_mass / m
	var cot := 10.7 * pow(m, -0.32)  # J/(kg*m), Taylor et al. 1982
	lp.cost_walk = cot * m * load
	lp.cost_crawl = cot * m * load * 2.2
	lp.cost_swim = 0.7 * pow(m, -0.33) * m * (1.0 + cd * 2.0)
	if not lp.can_walk and not lp.can_crawl and not lp.can_swim and not lp.can_fly:
		lp._note(&"critical", "Организм не способен передвигаться: нет опорных конечностей, гибкого тела, плавников или крыльев.")
	return lp
