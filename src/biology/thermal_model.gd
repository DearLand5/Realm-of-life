class_name ThermalModel
extends RefCounted
## Heat balance of a body (Newtonian conductance model):
##   heat loss  Q = C · (T_body − T_env),  C = A / R_total
##   R_total    = boundary layer + covering insulation + subcutaneous fat
##   gains      = metabolic heat + absorbed sunlight (darker = more)
## Ectotherms thermoregulate behaviourally (sun/shade) inside the range the
## environment allows; endotherms additionally pay for thermogenesis below
## their thermoneutral zone and dump heat by vasodilation, then by water
## evaporation above it. Partial endothermy blends both. Outputs: body
## temperature, extra power, water for cooling, heat/cold stress and the
## ectotherm performance (speed/activity factor).

const SPECIFIC_HEAT := 3500.0       # J/(kg·K) of tissue
const R_BOUNDARY_AIR := 0.06        # m²K/W
const R_PER_INSULATION_AIR := 0.7   # m²K/W per unit of covering insulation
const R_FAT_AIR := 1.2              # m²K/W per unit fat mass fraction
const R_BOUNDARY_WATER := 0.008
const R_PER_INSULATION_WATER := 0.08  # wet fur/feathers lose most insulation
const R_FAT_WATER := 2.5            # blubber keeps working in water
const GILL_HEAT_EXCHANGE := 400.0   # W/K per m² of gill area (gills are radiators)
const ENDO_SET_TEMP := 37.5         # °C body set point of a full endotherm
const SOLAR_FLUX := 550.0           # W/m² absorbed at full light on land
const EVAP_W_PER_M2 := 90.0         # max evaporative cooling per m² (sweat/panting)
const LATENT_HEAT := 2.4e6          # J/kg of evaporated water
const THERMOGENIC_SCOPE := 5.0      # summit metabolism / BMR of a full endotherm
const VASO_RANGE := 2.5             # conductance can rise ×2.5 by vasodilation


class Result:
	var body_temp: float = 20.0
	var target_temp: float = 20.0     # regulated (steady) body temperature
	var extra_w: float = 0.0          # thermoregulation power above metabolic heat
	var cooling_water: float = 0.0    # kg/s evaporated for cooling
	var heat_stress: float = 0.0      # 0..1
	var cold_stress: float = 0.0      # 0..1
	var performance: float = 1.0      # 0..1 activity/speed factor
	var conductance: float = 1.0      # W/K actually used


static func build(p: PhysiologyProfile, ph: Phenotype) -> void:
	var st := ph.anatomy.stats
	var g := ph.genome
	var area := float(st.get("surface_area", 0.1))
	var wing := float(st.get("wing_area", 0.0))
	var fin := float(st.get("fin_area", 0.0))
	# Folded wings / thin fins are poorly perfused: most of their area does not lose heat.
	p.thermal_area = clampf(area - 1.5 * wing - 0.8 * fin, area * 0.35, area)
	p.projected_area = p.thermal_area * 0.3
	var ins := float(st.get("insulation", 0.1))
	p.insulation = ins
	p.fat_fraction = float(st.get("fat_mass", 0.0)) / maxf(p.mass, 1e-6)
	var r_air := R_BOUNDARY_AIR + R_PER_INSULATION_AIR * ins + R_FAT_AIR * p.fat_fraction
	var r_water := R_BOUNDARY_WATER + R_PER_INSULATION_WATER * ins + R_FAT_WATER * p.fat_fraction
	p.conductance_air = p.thermal_area / r_air
	p.conductance_water = p.thermal_area / r_water + p.gill_area * GILL_HEAT_EXCHANGE
	p.heat_capacity = p.mass * SPECIFIC_HEAT
	p.thermal_optimum = g.value(&"thermal_optimum")
	p.thermal_tolerance = g.value(&"thermal_tolerance")
	p.body_temp_set = lerpf(p.thermal_optimum, ENDO_SET_TEMP, p.endothermy)
	# Absorptivity from the brightness of the expressed coverings.
	var v_sum := 0.0
	var n := 0
	for c in ph.anatomy.coverings:
		v_sum += c.color_a.v * 0.7 + c.color_b.v * 0.3
		n += 1
	var v := v_sum / float(n) if n > 0 else 0.5
	p.absorptivity = clampf(1.0 - 0.75 * v, 0.25, 0.95)
	p.max_thermogenesis_w = pow(p.endothermy, 1.5) * THERMOGENIC_SCOPE * p.bmr_watts
	p.evap_cooling_w = p.thermal_area * EVAP_W_PER_M2 * lerpf(0.25, 1.0, p.endothermy) * (0.6 + p.thermal_tolerance / 25.0)


## Steady-state heat balance. heat_w = metabolic heat production (basal +
## activity) at the current mass. Writes into `out` (no allocations).
static func steady(p: PhysiologyProfile, t_env: float, in_water: bool, light: float, wind: float,
		heat_w: float, mass_factor: float, out: Result) -> void:
	var mf23 := pow(maxf(mass_factor, 1e-4), 2.0 / 3.0)
	var c := (p.conductance_water if in_water else p.conductance_air * (1.0 + 0.12 * sqrt(maxf(wind, 0.0)))) * mf23
	c = maxf(c, 1e-5)
	var sun := 0.0 if in_water else clampf(light, 0.0, 1.0) * SOLAR_FLUX * p.projected_area * p.absorptivity * mf23
	var h := maxf(heat_w, 0.0)
	var e := p.endothermy
	# Behavioural range (shade .. full sun).
	var lo := t_env + h / c
	var hi := lo + sun / c
	var t_eco := clampf(p.thermal_optimum, lo, hi)
	var sun_used := clampf((t_eco - lo) * c, 0.0, sun)
	var t_target := t_eco + e * (p.body_temp_set - t_eco)
	var need := c * (t_target - t_env) - sun_used - h
	var t_b := t_target
	out.extra_w = 0.0
	out.cooling_water = 0.0
	out.conductance = c
	if need > 0.0:
		var thermo := minf(need, p.max_thermogenesis_w * pow(maxf(mass_factor, 1e-4), 0.75))
		t_b = t_env + (h + sun_used + thermo) / c
		out.extra_w = thermo
	else:
		t_b = t_env + (h + sun_used) / c
		var t_cool := lerpf(p.thermal_optimum + 0.5 * p.thermal_tolerance, p.body_temp_set, e)
		if t_b > t_cool:
			# 1) vasodilation (free), 2) evaporation (costs water).
			var c_max := c * lerpf(1.2, VASO_RANGE, e)
			if t_cool > t_env + 0.1:
				var c_need := (h + sun_used) / (t_cool - t_env)
				var c_eff := clampf(c_need, c, c_max)
				out.conductance = c_eff
				t_b = t_env + (h + sun_used) / c_eff
			else:
				out.conductance = c_max
				t_b = t_env + (h + sun_used) / c_max
			if t_b > t_cool:
				var cool := minf(p.evap_cooling_w * mf23, out.conductance * (t_b - t_cool))
				t_b -= cool / out.conductance
				out.cooling_water = cool / LATENT_HEAT
				out.extra_w = cool * 0.03
	out.target_temp = t_b
	out.body_temp = t_b
	_stress(p, t_b, out)


## Stress and performance for a given body temperature.
static func _stress(p: PhysiologyProfile, t_b: float, out: Result) -> void:
	var e := p.endothermy
	var t_upper := lerpf(p.thermal_optimum + 1.2 * p.thermal_tolerance, p.body_temp_set + 3.5, e)
	var t_lower := lerpf(p.thermal_optimum - 2.2 * p.thermal_tolerance, p.body_temp_set - 5.0, e)
	out.heat_stress = clampf((t_b - t_upper) / 4.0, 0.0, 1.0)
	out.cold_stress = clampf((t_lower - t_b) / 6.0, 0.0, 1.0)
	out.performance = performance(p, t_b, out.heat_stress, out.cold_stress)


static func performance(p: PhysiologyProfile, t_b: float, heat_stress: float, cold_stress: float) -> float:
	var d := t_b - p.thermal_optimum
	var w := 1.2 * p.thermal_tolerance if d < 0.0 else 0.6 * p.thermal_tolerance
	var ecto := exp(-0.5 * (d / maxf(w, 0.5)) * (d / maxf(w, 0.5)))
	var endo := clampf(1.0 - 0.8 * cold_stress - 0.5 * heat_stress, 0.0, 1.0)
	return clampf(lerpf(ecto, endo, p.endothermy), 0.02, 1.0)


## Stress/performance for an arbitrary (dynamic) body temperature.
static func evaluate_temp(p: PhysiologyProfile, t_b: float, out: Result) -> void:
	out.body_temp = t_b
	_stress(p, t_b, out)


## Thermal time constant (s) of the body at a mass factor.
static func time_constant(p: PhysiologyProfile, conductance: float, mass_factor: float) -> float:
	return p.heat_capacity * mass_factor / maxf(conductance, 1e-5)
