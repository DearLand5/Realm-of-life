class_name DietModel
extends RefCounted
## Feeding apparatus → what an organism can actually digest.
## Efficiency of each food kind = digestion trait × mouth type × dentition ×
## digestive organs (stomach/gut/gizzard volumes → fermentation, capacity,
## retention). The diet category is DERIVED from these efficiencies and the
## behavioural preference; the plan's declared diet is only compared with it.

const TEETH_PLANT := {"grinding": 1.0, "mixed": 0.85, "none": 0.7, "cutting": 0.6, "fangs": 0.45}
const TEETH_MEAT := {"fangs": 1.0, "cutting": 1.0, "mixed": 0.85, "none": 0.7, "grinding": 0.5}
const MOUTH_PLANT := {"jaws": 1.0, "beak": 0.9, "mandibles": 1.0, "radula": 0.9, "proboscis": 0.6,
	"filter": 0.3, "sucker": 0.5, "cell_mouth": 0.8, "none": 0.0}
const MOUTH_MEAT := {"jaws": 1.0, "beak": 0.9, "mandibles": 1.0, "radula": 0.6, "proboscis": 0.5,
	"filter": 0.3, "sucker": 0.6, "cell_mouth": 0.7, "none": 0.0}
const MOUTH_DETRITUS := {"sucker": 1.0, "radula": 1.0, "cell_mouth": 1.0, "mandibles": 0.8,
	"jaws": 0.55, "filter": 0.6, "beak": 0.4, "proboscis": 0.5, "none": 0.0}
const MOUTH_FILTER := {"filter": 1.0, "cell_mouth": 0.8, "sucker": 0.35, "proboscis": 0.2,
	"jaws": 0.12, "beak": 0.05, "mandibles": 0.05, "radula": 0.2, "none": 0.0}
const PHOTO_W_PER_M2 := 100.0        # W per m² of exposed photosynthetic surface at full light
const INTAKE_COEF := 2.5e-4          # kg/s per kg^0.75 (handling-limited wet intake)
const GLYCOGEN_FRACTION := 0.01      # body mass fraction of glycogen
const GLYCOGEN_ENERGY := 1.7e7       # J/kg
## Only part of body fat is a readily mobilizable reserve (the rest is
## structural/insulating fat). Keeps fasting endurance proportional to the
## compressed game life history (see docs in PhysiologyProfile).
const RESERVE_FRACTION := 0.3


static func build(p: PhysiologyProfile, ph: Phenotype) -> void:
	var g := ph.genome
	var st := ph.anatomy.stats
	var organs: Dictionary = st.get("organ_volume", {})
	var mouth: Dictionary = st.get("mouth", {})
	var m_type := str(mouth.get("type", "none"))
	var teeth := str(mouth.get("teeth", "none"))
	var has_mouth := int(mouth.get("count", 0)) > 0
	if not has_mouth:
		m_type = "none"
	var vol := maxf(float(st.get("volume", 1e-6)), 1e-9)
	var stomach := float(organs.get("stomach", 0.0))
	var gut := float(organs.get("gut", 0.0))
	var gizzard := float(organs.get("gizzard", 0.0))
	var liver := float(organs.get("liver", 0.0))
	# Fermentation chamber size relative to the body drives plant digestion.
	var ferment := (gut + gizzard * 1.5 + stomach * 0.5) / vol
	var gut_plant := clampf(0.55 + ferment * 4.0, 0.5, 1.15)
	var acid := 1.05 if stomach > 0.0 else 0.95
	var detox := 1.0 + clampf(liver / vol * 20.0, 0.0, 0.3)
	var d_plant := g.value(&"digestion_plant")
	var d_meat := g.value(&"digestion_meat")
	var d_carrion := g.value(&"digestion_carrion")
	var plant := d_plant * float(TEETH_PLANT.get(teeth, 0.7)) * float(MOUTH_PLANT.get(m_type, 0.5)) * gut_plant
	# Gizzards grind food for toothless beaks.
	if gizzard > 0.0 and teeth == "none":
		plant *= 1.2
	var meat := d_meat * float(TEETH_MEAT.get(teeth, 0.7)) * float(MOUTH_MEAT.get(m_type, 0.5)) * acid
	var carrion := clampf(d_carrion * 0.6 + d_meat * 0.4, 0.0, 1.0) * float(MOUTH_MEAT.get(m_type, 0.5)) * acid * detox
	var detritus := maxf(d_plant, d_carrion) * float(MOUTH_DETRITUS.get(m_type, 0.5)) * clampf(0.6 + ferment * 3.0, 0.6, 1.1)
	var filter := maxf(d_plant, d_meat) * float(MOUTH_FILTER.get(m_type, 0.1))
	# Gills of aquatic animals also sieve plankton when the mouth is a filter.
	if m_type == "filter" and p.gill_area > 0.0:
		filter *= 1.15
	var photo_tissue := float(organs.get("photo_tissue", 0.0))
	var photo := g.value(&"photosynthesis") * clampf(0.15 + photo_tissue / vol * 4.0, 0.0, 1.0)
	p.diet_eff = {
		"plant": clampf(plant, 0.0, 0.95), "meat": clampf(meat, 0.0, 0.95), "carrion": clampf(carrion, 0.0, 0.95),
		"detritus": clampf(detritus, 0.0, 0.9), "filter": clampf(filter, 0.0, 0.95), "photo": clampf(photo, 0.0, 1.0),
	}
	p.diet_preference = g.value(&"diet_preference")
	p.declared_diet = StringName(str(g.body_plan.bio("diet")))
	p.mouth_type = StringName(m_type)
	p.teeth = StringName(teeth)
	# Capacity & intake.
	var cap_vol := stomach + gizzard * 0.7 + gut * 0.6
	p.gut_capacity_kg = maxf(cap_vol * 1000.0, p.mass * 0.03) if cap_vol > 0.0 else p.mass * 0.04
	p.gut_retention_factor = clampf(sqrt(maxf(ferment, 0.01) / 0.1), 0.5, 2.0)
	var ratio := float(mouth.get("size", 0.0)) / maxf(pow(p.mass, 1.0 / 3.0), 1e-4)
	var mouth_factor := clampf(sqrt(ratio / 0.01), 0.5, 1.6) if has_mouth else 0.3
	p.max_intake_kg_s = INTAKE_COEF * pow(p.mass, 0.75) * mouth_factor
	# Photosynthesis: half the surface faces the light.
	p.photo_w = float(st.get("surface_area", 0.0)) * 0.5 * PHOTO_W_PER_M2 * float(p.diet_eff["photo"])
	p.free_energy_w = maxf(0.0, float(g.body_plan.rule("free_energy"))) * p.mass
	# Energy reserve.
	var fat := float(st.get("fat_mass", p.mass * 0.08))
	p.max_energy = fat * RESERVE_FRACTION * Units.FAT_ENERGY + p.mass * GLYCOGEN_FRACTION * GLYCOGEN_ENERGY
	p.diet = derive_diet(p)


## Diet category from digestive abilities + preference (not from the label).
static func derive_diet(p: PhysiologyProfile) -> StringName:
	var e := p.diet_eff
	var plant := float(e["plant"])
	var meat := float(e["meat"])
	var carrion := float(e["carrion"])
	var detritus := float(e["detritus"])
	var filter := float(e["filter"])
	var photo := float(e["photo"])
	var pref := p.diet_preference
	var best := maxf(maxf(plant, meat), maxf(detritus, filter))
	if photo > 0.3 and photo >= best * 0.8:
		return &"photosynth"
	if p.declared_diet == &"parasite" and p.mouth_type in [&"proboscis", &"sucker"]:
		return &"parasite"
	if filter >= best and filter > 0.25:
		return &"filter"
	if detritus >= best and detritus > plant * 1.1:
		return &"detritivore"
	var animal_score := meat * (0.3 + pref)
	var plant_score := plant * (1.3 - pref)
	if carrion > 0.45 and carrion >= meat * 0.8 and pref > 0.45 and p.weapon_score < 2.0:
		return &"scavenger"
	if animal_score > plant_score * 2.0:
		return &"carnivore"
	if plant_score > animal_score * 2.0:
		return &"herbivore"
	return &"omnivore"


## Diet preference weights per Food kind (0..1): what the organism tries to eat.
static func food_weights(p: PhysiologyProfile, out: PackedFloat32Array) -> void:
	out.resize(Food.COUNT)
	var pref := p.diet_preference
	out[Food.PLANT] = float(p.diet_eff["plant"]) * clampf(1.3 - pref, 0.0, 1.0)
	out[Food.MEAT] = float(p.diet_eff["meat"]) * clampf(0.3 + pref, 0.0, 1.0)
	out[Food.CARRION] = float(p.diet_eff["carrion"]) * clampf(0.2 + pref, 0.0, 1.0)
	out[Food.DETRITUS] = float(p.diet_eff["detritus"]) * (1.0 if p.diet == &"detritivore" else 0.3)
	out[Food.PLANKTON] = float(p.diet_eff["filter"])
