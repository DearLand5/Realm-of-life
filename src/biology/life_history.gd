class_name LifeHistory
extends RefCounted
## Life-history schedule from allometry and traits.
##
## Game time model: life history is compressed (a lifespan lasts game DAYS,
## not years) while metabolic power stays in real watts. Allometric exponents
## are kept (lifespan, maturity, gestation ∝ M^0.2), so large species still
## live longer and breed slower than small ones.
##   stages: egg/embryo → juvenile → adolescent → adult → elder
##   growth: von Bertalanffy in length, L(t) = 1 − (1 − L0)·e^(−k t)
##           (k set so that ~90 % of adult mass is reached at maturity)
##   r/K:    clutch × per-offspring investment ≤ MAX_REPRO_FRACTION of body mass
##   senescence: Gompertz hazard μ(a) = (A/L)·e^(B·a/L)
##   feasibility: development (growing up, embryos, eggs) cannot be faster
##           than the parent's gut can pay for — poor digesters develop slowly.

const STAGES: Array[StringName] = [&"egg", &"juvenile", &"adolescent", &"adult", &"elder"]
const MAX_REPRO_FRACTION := 0.6      # body-mass fraction invested per breeding event
const GOMPERTZ_A := 0.0448           # with B = 6: median death ≈ 0.76 L, 5 % survive to L
const GOMPERTZ_B := 6.0
const ELDER_FRACTION := 0.75         # of lifespan
const JUVENILE_SHARE := 0.45         # of the time to maturity
const DAY := Units.SECONDS_PER_DAY
const REPRO_INCOME_SHARE := 0.5      # share of production power that can fund embryos
const GROWTH_INCOME_SHARE := 0.25    # average share available for juvenile growth


static func build(p: PhysiologyProfile, ph: Phenotype) -> void:
	var g := ph.genome
	var plan := g.body_plan
	var m := p.mass
	var met := g.value(&"metabolism")
	# Rate of living: fast metabolism shortens life; endotherms (esp. birds) are long-lived for their size.
	# Ectotherms live longer than endotherms of the same size.
	var base_days := (8.0 + 10.0 * pow(m, 0.2)) * (1.3 - 0.3 * p.endothermy)
	p.lifespan = base_days * g.value(&"lifespan") / sqrt(met) * DAY
	var growth_rate := g.value(&"growth_rate")
	p.maturity_age = p.lifespan * 0.18 * g.value(&"maturity_age") / sqrt(growth_rate)
	var grow_min := m * Food.BUILD_COST / maxf(GROWTH_INCOME_SHARE * p.production_w, 1e-9)
	p.maturity_age = maxf(p.maturity_age, minf(grow_min, p.lifespan * 0.45))
	p.juvenile_s = p.maturity_age * JUVENILE_SHARE
	p.elder_age = p.lifespan * ELDER_FRACTION
	p.repro_mode = StringName(str(plan.bio("reproduction_mode")))
	p.repro_method = StringName(str(plan.bio("reproduction_method")))
	p.metamorphosis = bool(plan.bio("metamorphosis"))
	p.molting = bool(plan.bio("molting"))
	p.fertility = g.value(&"fertility")
	p.breeding_season = g.value(&"breeding_season")
	# r/K trade-off: total investment per event is capped by body mass.
	var invest := g.value(&"offspring_investment")
	var clutch := g.value(&"clutch_size")
	match p.repro_method:
		&"fission":
			clutch = 1.0
			invest = 0.5
		&"budding":
			clutch = maxf(1.0, round(clutch * 0.3))
			invest = minf(invest, 0.25)
		&"spores":
			clutch = clutch * 4.0
			invest = minf(invest, 0.02)
	if clutch * invest > MAX_REPRO_FRACTION:
		clutch = maxf(1.0, MAX_REPRO_FRACTION / invest)
	p.clutch = clutch
	p.offspring_fraction = invest
	p.birth_growth = pow(invest, 1.0 / 3.0)
	var gest := g.value(&"gestation")
	var m20 := pow(m, 0.2)
	# Bigger investment per offspring needs longer development.
	var dev := gest * pow(invest / 0.1, 0.3)
	p.gestation_s = 0.5 * m20 * dev * DAY
	p.incubation_s = 0.35 * m20 * dev * DAY
	p.egg_formation_s = maxf(0.1 * DAY, p.incubation_s * 0.2)
	match p.repro_method:
		&"live":
			p.incubation_s = 0.0
		&"eggs", &"spores":
			p.gestation_s = 0.0
		_:
			p.gestation_s = 0.15 * m20 * DAY
			p.incubation_s = 0.0
	if p.repro_method == &"spores":
		p.incubation_s = 0.3 * DAY
		p.egg_formation_s = 0.2 * DAY
	# Embryos cannot be built faster than the parent's income allows.
	var fund := offspring_cost(p) * clutch / maxf(REPRO_INCOME_SHARE * p.production_w, 1e-9)
	match p.repro_method:
		&"live":
			p.gestation_s = maxf(p.gestation_s, fund)
		&"eggs", &"spores":
			p.egg_formation_s = maxf(p.egg_formation_s, fund)
		&"budding":
			p.gestation_s = maxf(p.gestation_s, fund)
	# Breeding must stay possible within a lifetime (runtime O2/energy throttling still applies).
	p.gestation_s = minf(p.gestation_s, p.lifespan * 0.15)
	p.egg_formation_s = minf(p.egg_formation_s, p.lifespan * 0.15)
	# Recovery between breeding events grows with the investment of the event.
	var event_frac := clutch * invest
	p.repro_cooldown_s = maxf(0.2 * DAY, p.maturity_age * 0.12 * sqrt(event_frac / 0.3))
	# von Bertalanffy: L(T_mat) reaches 0.9^(1/3) of adult length.
	var l0 := p.birth_growth
	var target := (1.0 - pow(0.9, 1.0 / 3.0)) / maxf(1.0 - l0, 1e-3)
	p.growth_k = -log(clampf(target, 1e-4, 0.99)) / maxf(p.maturity_age, 1.0)
	p.molt_interval_s = p.maturity_age / 5.0 if p.molting else 0.0


## Stage label for an age (not counting eggs).
static func stage_for_age(p: PhysiologyProfile, age: float) -> StringName:
	if age < p.juvenile_s:
		return &"juvenile"
	if age < p.maturity_age:
		return &"adolescent"
	if age < p.elder_age:
		return &"adult"
	return &"elder"


## Expected linear growth (0..1) of a well-fed individual at an age.
static func expected_growth(p: PhysiologyProfile, age: float) -> float:
	return 1.0 - (1.0 - p.birth_growth) * exp(-p.growth_k * maxf(age, 0.0))


## Gompertz mortality hazard per biological second.
static func hazard(p: PhysiologyProfile, age: float) -> float:
	var x := age / maxf(p.lifespan, 1.0)
	return GOMPERTZ_A / maxf(p.lifespan, 1.0) * exp(GOMPERTZ_B * minf(x, 3.0))


## Mean Gompertz hazard over the elder stage (pool tier).
static func elder_hazard(p: PhysiologyProfile) -> float:
	# Average of μ over x ∈ [0.75, 1.25] (elders rarely live longer).
	var a := GOMPERTZ_A / maxf(p.lifespan, 1.0)
	var x0 := ELDER_FRACTION
	var x1 := 1.25
	return a * (exp(GOMPERTZ_B * x1) - exp(GOMPERTZ_B * x0)) / (GOMPERTZ_B * (x1 - x0))


## Energy (J) a parent spends on ONE offspring (tissue + starting reserve).
static func offspring_cost(p: PhysiologyProfile) -> float:
	var om := p.mass * p.offspring_fraction
	return om * Food.BUILD_COST + p.max_energy * p.offspring_fraction * 0.5


## Total development time from conception to independent juvenile.
static func development_time(p: PhysiologyProfile) -> float:
	return p.gestation_s + p.incubation_s + p.egg_formation_s * (1.0 if p.incubation_s > 0.0 else 0.0)
