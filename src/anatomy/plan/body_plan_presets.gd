class_name BodyPlanPresets
extends RefCounted
## Starter organisms covering very different body organisations. Each preset
## returns a founder Genome (body plan + homozygous trait values). Used by the
## editor ("Пресеты"), tutorials, tests and the procedural fauna generator.
##
## Frame reminder (see AnatomyCompiler.attach_frame):
##   attach_angle: 0 right, 90 dorsal, 180 left, 270 ventral
##   mid attachments: part pitch tilts around the parent axis (−pitch on the
##   right side = downwards), part yaw sweeps forward (+) / backward (−).
##   end attachments (t=0/1, depth≈0): pitch + = up.

const IDS: Array[StringName] = [
	&"grazer", &"predator", &"runner", &"bird", &"fish", &"frog", &"turtle", &"worm",
	&"centipede", &"insect", &"spider", &"octopus", &"jellyfish", &"starfish", &"cell",
]

const LABELS := {
	&"grazer": "Травоед-четвероног", &"predator": "Хищник-четвероног", &"runner": "Двуногий бегун",
	&"bird": "Птица", &"fish": "Рыба", &"frog": "Амфибия", &"turtle": "Черепаха", &"worm": "Червь",
	&"centipede": "Многоножка", &"insect": "Летающее насекомое", &"spider": "Паукообразное",
	&"octopus": "Головоногое", &"jellyfish": "Медуза", &"starfish": "Морская звезда",
	&"cell": "Одноклеточное",
}

const DESCRIPTIONS := {
	&"grazer": "Копытное с рогами, стадное, питается растениями.",
	&"predator": "Гибкий кошачий хищник с острыми зубами и когтями.",
	&"runner": "Оперённый двуногий всеядный бегун с балансирующим хвостом.",
	&"bird": "Лёгкое летающее существо с перьевыми крыльями и клювом.",
	&"fish": "Обтекаемое тело, плавники, жабры, чешуя.",
	&"frog": "Прыгучая амфибия: влажная кожа, лёгкие и кожное дыхание.",
	&"turtle": "Медленное бронированное животное с панцирем.",
	&"worm": "Сегментированное безногое тело, кожное дыхание, питается детритом.",
	&"centipede": "Метамерное тело с повторяющимися парами ног.",
	&"insect": "Хитиновый экзоскелет, шесть ног, трахеи, фасеточные глаза.",
	&"spider": "Восемь ног, простые глаза, яд и шёлковые железы.",
	&"octopus": "Радиально расположенные щупальца с присосками, крупный мозг.",
	&"jellyfish": "Радиальная симметрия, студенистый колокол, фильтрация.",
	&"starfish": "Пятилучевая симметрия, ползает на щупальцах-лучах.",
	&"cell": "Абстрактная клеточная модель: мембрана, органеллы, жгутик.",
}


static func create(id: StringName) -> Genome:
	match id:
		&"grazer": return _grazer()
		&"predator": return _predator()
		&"runner": return _runner()
		&"bird": return _bird()
		&"fish": return _fish()
		&"frog": return _frog()
		&"turtle": return _turtle()
		&"worm": return _worm()
		&"centipede": return _centipede()
		&"insect": return _insect()
		&"spider": return _spider()
		&"octopus": return _octopus()
		&"jellyfish": return _jellyfish()
		&"starfish": return _starfish()
		&"cell": return _cell()
	push_warning("BodyPlanPresets: unknown preset %s" % id)
	return _grazer()


static func label(id: StringName) -> String:
	return LABELS.get(id, str(id))


# --- Builder helpers ------------------------------------------------------------------

## segs: Array of [length, end_radius, pitch, yaw, flatten?, roll?]
static func chain(kind: StringName, base_r: float, segs: Array, fn: StringName = &"none") -> BodyPart:
	var p := BodyPart.new(kind)
	p.base_radius = base_r
	p.function = fn
	for sd in segs:
		var s := BodySegment.new(float(sd[0]), float(sd[1]), float(sd[2]) if sd.size() > 2 else 0.0, float(sd[3]) if sd.size() > 3 else 0.0)
		if sd.size() > 4:
			s.flatten = float(sd[4])
		if sd.size() > 5:
			s.roll = float(sd[5])
		p.segments.append(s)
	return p


static func point(kind: StringName, params: Dictionary = {}) -> BodyPart:
	var p := BodyPart.new(kind)
	for k in params:
		p.set_param(k, params[k])
	return p


## Attaches `part` to `parent` and returns its id.
static func att(plan: BodyPlan, part: BodyPart, parent: int, t: float, angle: float, depth: float,
		sym: int = 0, pitch: float = 0.0, yaw: float = 0.0, roll: float = 0.0, label_text: String = "") -> int:
	part.attach_t = t
	part.attach_angle = angle
	part.attach_depth = depth
	part.symmetry = sym
	part.pitch = pitch
	part.yaw = yaw
	part.roll = roll
	part.label = label_text
	return plan.add_part(part, parent)


static func organ(plan: BodyPlan, parent: int, organ_type: String, t: float, size: float, angle: float = 90.0, depth: float = 0.3) -> int:
	return att(plan, point(&"organ", {"organ_type": organ_type, "size": size}), parent, t, angle, depth)


static func _finish(plan: BodyPlan, traits: Dictionary) -> Genome:
	plan.repair()
	var g := Genome.new(plan)
	for k in traits:
		g.set_value(StringName(k), float(traits[k]))
	return g


static func _set_muscle(part: BodyPart, ratio: float, fast: float) -> BodyPart:
	part.muscle_ratio = ratio
	part.fast_twitch = fast
	return part


static func _head_senses(plan: BodyPlan, head: int, eye: Dictionary, eye_t: float, eye_angle: float, eye_yaw: float, mouth: Dictionary) -> void:
	att(plan, point(&"eye", eye), head, eye_t, eye_angle, 0.9, 1, 0.0, eye_yaw, 0.0, "Глаз")
	att(plan, point(&"mouth", mouth), head, 1.0, 270.0, 0.45, 0, 0.0, 0.0, 0.0, "Рот")
	att(plan, point(&"nose", {"sensitivity": 0.6}), head, 1.0, 90.0, 0.35)


# --- Presets ---------------------------------------------------------------------------

static func _grazer() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Рогатый травоед"
	plan.coverings = [
		CoveringDef.make(&"fur", Color(0.55, 0.38, 0.22), Color(0.92, 0.86, 0.72), &"countershade"),
		CoveringDef.make(&"skin", Color(0.2, 0.17, 0.15), Color(0.35, 0.3, 0.27), &"none"),
		CoveringDef.make(&"plates", Color(0.82, 0.76, 0.62), Color(0.45, 0.4, 0.33), &"gradient"),
	]
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "live", "diet": "herbivore"}
	var torso := chain(&"torso", 0.16, [[0.30, 0.2, 0, 0, 1.15], [0.36, 0.215, 4, 0, 1.15], [0.30, 0.18, 4, 0, 1.1]])
	var t := plan.add_part(torso)
	var neck := att(plan, chain(&"neck", 0.15, [[0.22, 0.1, 42], [0.2, 0.085, 10]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Шея")
	var head := att(plan, chain(&"head", 0.09, [[0.16, 0.1, -68], [0.17, 0.055, -8]]), neck, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Голова")
	_head_senses(plan, head, {"eye_type": "camera", "size": 0.32, "fov": 195.0, "acuity": 0.6, "night_vision": 0.4, "iris_color": Color(0.3, 0.2, 0.1)},
		0.42, 28.0, 25.0, {"mouth_type": "jaws", "teeth": "grinding", "bite_force": 0.3, "size": 0.6})
	att(plan, point(&"ear", {"ear_type": "external", "size": 0.7, "sensitivity": 0.7}), head, 0.22, 62.0, 0.95, 1, 10.0, -25.0, 0.0, "Ухо")
	var horn := point(&"horn", {"length": 2.6, "base": 0.3, "curvature": 0.45, "sharpness": 0.6})
	horn.covering = 2
	att(plan, horn, head, 0.18, 78.0, 0.95, 1, 8.0, -38.0, 0.0, "Рог")
	for spec in [[0.86, "Передняя нога", [[0.30, 0.055, 0, -6], [0.30, 0.04, 0, 6], [0.14, 0.03, 0, 18]]],
			[0.12, "Задняя нога", [[0.32, 0.062, 0, 16], [0.30, 0.04, 0, -36], [0.16, 0.03, 0, 26]]]]:
		var leg := _set_muscle(chain(&"limb", 0.075, spec[2], &"run"), 0.5, 0.6)
		leg.set_param("foot", "hoof")
		leg.covering = 0
		att(plan, leg, t, spec[0], 300.0, 0.72, 1, -26.0, 0.0, 0.0, spec[1])
	att(plan, chain(&"tail", 0.05, [[0.12, 0.04, -28], [0.1, 0.022, -12]]), t, 0.0, 0.0, 0.0, 0, 0, 0, 0, "Хвост")
	organ(plan, t, "lungs", 0.72, 0.12)
	organ(plan, t, "heart", 0.75, 0.03, 270.0, 0.2)
	organ(plan, t, "stomach", 0.48, 0.14, 270.0, 0.25)
	organ(plan, t, "gut", 0.28, 0.16, 270.0, 0.2)
	organ(plan, t, "gonads", 0.08, 0.02, 270.0, 0.3)
	organ(plan, head, "brain", 0.3, 0.18, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.05, "digestion_plant": 0.85, "digestion_meat": 0.08, "endothermy": 0.95,
		"thermal_optimum": 14.0, "thermal_tolerance": 15.0, "sociality": 0.8, "aggression": 0.15, "boldness": 0.3,
		"vigilance": 0.8, "clutch_size": 1.3, "offspring_investment": 0.12, "lifespan": 1.2, "breeding_season": 0.7,
		"activity_phase": 0.15, "territoriality": 0.2})


static func _predator() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Пятнистый хищник"
	plan.coverings = [
		CoveringDef.make(&"fur", Color(0.8, 0.62, 0.32), Color(0.22, 0.15, 0.08), &"rosettes"),
		CoveringDef.make(&"skin", Color(0.25, 0.18, 0.16), Color(0.4, 0.3, 0.28), &"none"),
	]
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "live", "diet": "carnivore"}
	var torso := _set_muscle(chain(&"torso", 0.14, [[0.27, 0.17, 0, 0, 1.05], [0.3, 0.19, 3, 0, 1.05], [0.25, 0.17, 2, 0, 1.0]]), 0.45, 0.7)
	var t := plan.add_part(torso)
	var neck := att(plan, chain(&"neck", 0.13, [[0.14, 0.1, 18]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Шея")
	var head := att(plan, chain(&"head", 0.1, [[0.13, 0.11, -20], [0.1, 0.065, -6]]), neck, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Голова")
	_head_senses(plan, head, {"eye_type": "camera", "size": 0.3, "fov": 145.0, "acuity": 0.85, "night_vision": 0.8, "pupil": "slit", "iris_color": Color(0.85, 0.7, 0.15)},
		0.62, 34.0, 55.0, {"mouth_type": "jaws", "teeth": "fangs", "bite_force": 0.9, "size": 0.75})
	att(plan, point(&"ear", {"ear_type": "external", "size": 0.45, "sensitivity": 0.8}), head, 0.2, 64.0, 0.95, 1, 5.0, -10.0, 0.0, "Ухо")
	att(plan, point(&"whisker", {"length": 1.6, "count": 5}), head, 0.88, 15.0, 0.9, 1, 0.0, -30.0)
	for spec in [[0.85, "Передняя лапа", [[0.24, 0.055, 0, -4], [0.24, 0.04, 0, 4], [0.09, 0.032, 0, 50]]],
			[0.1, "Задняя лапа", [[0.27, 0.065, 0, 22], [0.25, 0.042, 0, -42], [0.12, 0.03, 0, 28]]]]:
		var leg := _set_muscle(chain(&"limb", 0.07, spec[2], &"run"), 0.55, 0.85)
		leg.set_param("foot", "claw")
		var lid := att(plan, leg, t, spec[0], 300.0, 0.72, 1, -26.0, 0.0, 0.0, spec[1])
		att(plan, point(&"claw", {"length": 0.9, "curvature": 0.7, "sharpness": 0.9}), lid, 1.0, 270.0, 0.6, 0, 0.0, 0.0)
	att(plan, chain(&"tail", 0.05, [[0.16, 0.045, -18], [0.16, 0.035, 6], [0.15, 0.03, 8], [0.14, 0.022, 6], [0.12, 0.015, 4]]), t, 0.0, 0.0, 0.0, 0, 0, 0, 0, "Хвост")
	organ(plan, t, "lungs", 0.75, 0.14)
	organ(plan, t, "heart", 0.78, 0.035, 270.0, 0.2)
	organ(plan, t, "stomach", 0.5, 0.1, 270.0, 0.25)
	organ(plan, t, "gut", 0.3, 0.08, 270.0, 0.2)
	organ(plan, t, "gonads", 0.08, 0.02, 270.0, 0.3)
	organ(plan, head, "brain", 0.3, 0.22, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.95, "digestion_plant": 0.08, "digestion_meat": 0.9, "digestion_carrion": 0.3,
		"endothermy": 0.95, "thermal_optimum": 20.0, "aggression": 0.7, "boldness": 0.75, "sociality": 0.25,
		"territoriality": 0.7, "clutch_size": 3.0, "offspring_investment": 0.06, "activity_phase": 0.6, "night_vision": 0.7,
		"vigilance": 0.5, "parental_care": 0.8, "muscle_mass": 1.15})


static func _runner() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Оперённый бегун"
	plan.coverings = [
		CoveringDef.make(&"feathers", Color(0.16, 0.45, 0.42), Color(0.95, 0.6, 0.2), &"stripes"),
		CoveringDef.make(&"scales", Color(0.5, 0.4, 0.25), Color(0.3, 0.25, 0.15), &"none"),
	]
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "omnivore"}
	var t := plan.add_part(chain(&"torso", 0.1, [[0.22, 0.14, 0, 0, 1.1], [0.22, 0.15, 8, 0, 1.1]]))
	var neck := att(plan, chain(&"neck", 0.11, [[0.14, 0.07, 48], [0.14, 0.06, -12]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Шея")
	var head := att(plan, chain(&"head", 0.07, [[0.11, 0.07, -42], [0.12, 0.038, -4]]), neck, 1.0, 0.0, 0.0)
	_head_senses(plan, head, {"eye_type": "camera", "size": 0.38, "fov": 160.0, "acuity": 0.8, "iris_color": Color(0.9, 0.5, 0.1)},
		0.45, 32.0, 35.0, {"mouth_type": "jaws", "teeth": "cutting", "bite_force": 0.6, "size": 0.7})
	att(plan, point(&"ear", {"ear_type": "pit", "size": 0.3, "sensitivity": 0.7}), head, 0.15, 15.0, 0.95, 1)
	var leg := _set_muscle(chain(&"limb", 0.07, [[0.26, 0.06, 0, 26], [0.28, 0.04, 0, -48], [0.18, 0.025, 0, 28], [0.07, 0.02, 0, 64]], &"run"), 0.6, 0.85)
	leg.set_param("foot", "claw")
	leg.covering = 1
	att(plan, leg, t, 0.28, 300.0, 0.7, 1, -24.0, 0.0, 0.0, "Нога")
	var arm := chain(&"limb", 0.03, [[0.12, 0.025, 0, 35], [0.1, 0.018, 0, 40]], &"grasp")
	arm.set_param("foot", "hand")
	att(plan, arm, t, 0.88, 320.0, 0.8, 1, -15.0, 0.0, 0.0, "Рука")
	att(plan, chain(&"tail", 0.1, [[0.2, 0.08, -6], [0.2, 0.06, 2], [0.18, 0.04, 2], [0.16, 0.025, 0], [0.12, 0.012, 0]]), t, 0.0, 0.0, 0.0, 0, 0, 0, 0, "Хвост")
	organ(plan, t, "lungs", 0.7, 0.16)
	organ(plan, t, "heart", 0.72, 0.04, 270.0, 0.2)
	organ(plan, t, "gizzard", 0.45, 0.08, 270.0, 0.25)
	organ(plan, t, "gut", 0.25, 0.1, 270.0, 0.2)
	organ(plan, t, "gonads", 0.1, 0.02, 270.0, 0.3)
	organ(plan, head, "brain", 0.3, 0.2, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.6, "digestion_plant": 0.5, "digestion_meat": 0.7, "endothermy": 0.8,
		"thermal_optimum": 24.0, "sociality": 0.6, "aggression": 0.5, "boldness": 0.6, "clutch_size": 4.0,
		"offspring_investment": 0.05, "parental_care": 0.6})


static func _bird() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Пёстрая птица"
	plan.coverings = [
		CoveringDef.make(&"feathers", Color(0.72, 0.28, 0.18), Color(0.95, 0.88, 0.7), &"countershade"),
		CoveringDef.make(&"scales", Color(0.85, 0.62, 0.2), Color(0.6, 0.4, 0.15), &"none"),
		CoveringDef.make(&"feathers", Color(0.2, 0.22, 0.3), Color(0.85, 0.85, 0.9), &"bands"),
	]
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "omnivore"}
	var t := plan.add_part(_set_muscle(chain(&"torso", 0.045, [[0.08, 0.05, 0, 0, 1.1], [0.1, 0.042, 6, 0, 1.1]]), 0.5, 0.6))
	var neck := att(plan, chain(&"neck", 0.04, [[0.05, 0.03, 40], [0.04, 0.03, -10]]), t, 1.0, 0.0, 0.0)
	var head := att(plan, chain(&"head", 0.03, [[0.04, 0.035, -30], [0.03, 0.02, 0]]), neck, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Голова")
	att(plan, point(&"eye", {"eye_type": "camera", "size": 0.4, "fov": 170.0, "acuity": 0.95, "color_vision": 1.0, "iris_color": Color(0.1, 0.08, 0.05)}), head, 0.45, 25.0, 0.9, 1, 0.0, 20.0, 0.0, "Глаз")
	att(plan, point(&"ear", {"ear_type": "pit", "size": 0.2, "sensitivity": 0.7}), head, 0.2, 10.0, 0.95, 1)
	var beak := point(&"mouth", {"mouth_type": "beak", "size": 1.3, "teeth": "none", "bite_force": 0.4})
	beak.covering = 1
	att(plan, beak, head, 1.0, 270.0, 0.15, 0, 0, 0, 0, "Клюв")
	var wing := _set_muscle(chain(&"wing", 0.02, [[0.13, 0.018, 0, -8], [0.17, 0.013, 0, 16], [0.15, 0.007, 0, -22]], &"fly"), 0.7, 0.6)
	wing.set_param("wing_type", "feather")
	wing.set_param("chord", 0.62)
	wing.covering = 2
	att(plan, wing, t, 0.75, 62.0, 0.85, 1, -56.0, 0.0, 0.0, "Крыло")
	var leg := chain(&"limb", 0.014, [[0.06, 0.012, 0, 22], [0.07, 0.008, 0, -34], [0.03, 0.006, 0, 62]], &"walk")
	leg.set_param("foot", "claw")
	leg.covering = 1
	att(plan, leg, t, 0.35, 290.0, 0.7, 1, -20.0, 0.0, 0.0, "Лапа")
	var tail := chain(&"fin", 0.012, [[0.09, 0.01, -12]], &"none")
	tail.set_param("fin_type", "caudal")
	tail.set_param("fin_area", 1.6)
	tail.covering = 2
	att(plan, tail, t, 0.0, 0.0, 0.0, 0, 0, 0, 0, "Хвостовые перья")
	organ(plan, t, "lungs", 0.7, 0.18)
	organ(plan, t, "heart", 0.72, 0.05, 270.0, 0.2)
	organ(plan, t, "gizzard", 0.45, 0.08, 270.0, 0.25)
	organ(plan, t, "gonads", 0.15, 0.02, 270.0, 0.3)
	organ(plan, head, "brain", 0.3, 0.25, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.35, "digestion_plant": 0.6, "digestion_meat": 0.5, "endothermy": 1.0,
		"thermal_optimum": 18.0, "sociality": 0.75, "boldness": 0.4, "clutch_size": 4.0, "offspring_investment": 0.08,
		"parental_care": 0.8, "vigilance": 0.7, "fur_length": 1.2, "breeding_season": 0.8})


static func _fish() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Серебристая рыба"
	plan.coverings = [
		CoveringDef.make(&"scales", Color(0.25, 0.42, 0.55), Color(0.9, 0.92, 0.95), &"countershade"),
		CoveringDef.make(&"membrane", Color(0.55, 0.65, 0.75), Color(0.9, 0.5, 0.3), &"gradient"),
	]
	plan.coverings[0].iridescence = 0.5
	plan.biology = {"habitat": "water", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "omnivore"}
	var torso := _set_muscle(chain(&"torso", 0.04, [[0.12, 0.06, 0, 0, 1.7], [0.15, 0.068, 0, 0, 1.7], [0.15, 0.05, 0, 0, 1.6], [0.12, 0.022, 0, 0, 1.4]]), 0.6, 0.6)
	var t := plan.add_part(torso)
	var head := att(plan, chain(&"head", 0.055, [[0.09, 0.045, 0, 0, 1.4], [0.04, 0.025, -5, 0, 1.2]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Голова")
	att(plan, point(&"eye", {"eye_type": "camera", "size": 0.36, "fov": 175.0, "acuity": 0.6, "night_vision": 0.5, "iris_color": Color(0.8, 0.7, 0.3)}), head, 0.55, 22.0, 0.92, 1, 0.0, 15.0, 0.0, "Глаз")
	att(plan, point(&"mouth", {"mouth_type": "jaws", "teeth": "mixed", "size": 0.6, "bite_force": 0.3}), head, 1.0, 270.0, 0.25)
	att(plan, point(&"gill", {"area": 1.4, "slits": 4}), head, 0.1, 10.0, 0.97, 1, 0.0, 0.0, 0.0, "Жабры")
	att(plan, point(&"sensor", {"sensor_type": "vibration", "sensitivity": 0.7, "size": 0.1}), t, 0.6, 5.0, 0.98, 1, 0.0, 0.0, 0.0, "Боковая линия")
	var caudal := chain(&"fin", 0.025, [[0.13, 0.008, 0]], &"swim")
	caudal.set_param("fin_type", "caudal")
	caudal.set_param("fin_area", 2.2)
	caudal.covering = 1
	att(plan, caudal, t, 0.0, 0.0, 0.0, 0, 0, 0, 0, "Хвостовой плавник")
	var dorsal := chain(&"fin", 0.012, [[0.09, 0.006, 0, -45]], &"swim")
	dorsal.set_param("fin_type", "dorsal")
	dorsal.set_param("fin_area", 1.4)
	dorsal.covering = 1
	att(plan, dorsal, t, 0.58, 90.0, 0.95, 0, 0, 0, 0, "Спинной плавник")
	var pect := chain(&"fin", 0.01, [[0.07, 0.006, 0, -55]], &"swim")
	pect.set_param("fin_type", "pectoral")
	pect.set_param("fin_area", 1.2)
	pect.covering = 1
	att(plan, pect, t, 0.82, 330.0, 0.9, 1, -10.0, 0.0, 0.0, "Грудной плавник")
	var pelvic := chain(&"fin", 0.008, [[0.05, 0.005, 0, -50]], &"swim")
	pelvic.set_param("fin_type", "pelvic")
	pelvic.covering = 1
	att(plan, pelvic, t, 0.5, 285.0, 0.9, 1, 0.0, 0.0, 0.0, "Брюшной плавник")
	organ(plan, t, "swim_bladder", 0.6, 0.08, 90.0, 0.35)
	organ(plan, t, "heart", 0.88, 0.02, 270.0, 0.3)
	organ(plan, t, "gut", 0.55, 0.08, 270.0, 0.3)
	organ(plan, t, "gonads", 0.4, 0.04, 270.0, 0.3)
	organ(plan, head, "brain", 0.3, 0.1, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.4, "digestion_plant": 0.6, "digestion_meat": 0.6, "endothermy": 0.0,
		"thermal_optimum": 16.0, "thermal_tolerance": 10.0, "sociality": 0.85, "boldness": 0.3, "clutch_size": 12.0,
		"offspring_investment": 0.02, "parental_care": 0.05, "vigilance": 0.6})


static func _frog() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Прыгучая амфибия"
	plan.coverings = [
		CoveringDef.make(&"slime", Color(0.3, 0.55, 0.2), Color(0.1, 0.18, 0.08), &"spots"),
		CoveringDef.make(&"slime", Color(0.85, 0.82, 0.55), Color(0.4, 0.5, 0.2), &"none"),
	]
	plan.biology = {"habitat": "amphibious", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "carnivore", "metamorphosis": true}
	var t := plan.add_part(chain(&"torso", 0.04, [[0.06, 0.055, 4, 0, 0.75], [0.06, 0.05, 8, 0, 0.75]]))
	var head := att(plan, chain(&"head", 0.05, [[0.045, 0.05, -10, 0, 0.6], [0.03, 0.028, -5, 0, 0.55]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Голова")
	att(plan, point(&"eye", {"eye_type": "camera", "size": 0.5, "fov": 180.0, "acuity": 0.7, "night_vision": 0.5, "pupil": "horizontal", "iris_color": Color(0.9, 0.75, 0.2)}), head, 0.4, 55.0, 0.95, 1, 0.0, 10.0, 0.0, "Глаз")
	att(plan, point(&"mouth", {"mouth_type": "jaws", "teeth": "none", "size": 1.2, "bite_force": 0.3}), head, 1.0, 270.0, 0.4)
	att(plan, point(&"ear", {"ear_type": "tympanum", "size": 0.4}), head, 0.15, 30.0, 0.98, 1)
	var hind := _set_muscle(chain(&"limb", 0.022, [[0.07, 0.02, 0, 70], [0.075, 0.015, 0, -150], [0.06, 0.01, 0, 150], [0.04, 0.007, 0, -95]], &"run"), 0.65, 0.95)
	hind.set_param("foot", "web")
	hind.covering = 1
	att(plan, hind, t, 0.08, 320.0, 0.75, 1, -20.0, 0.0, 0.0, "Задняя лапа")
	var front := chain(&"limb", 0.014, [[0.04, 0.011, 0, -10], [0.04, 0.008, 0, 25]], &"walk")
	front.set_param("foot", "pad")
	front.covering = 1
	att(plan, front, t, 0.85, 300.0, 0.75, 1, -35.0, 0.0, 0.0, "Передняя лапа")
	organ(plan, t, "lungs", 0.65, 0.12)
	organ(plan, t, "heart", 0.75, 0.03, 270.0, 0.2)
	organ(plan, t, "stomach", 0.5, 0.1, 270.0, 0.25)
	organ(plan, t, "gonads", 0.2, 0.06, 270.0, 0.3)
	organ(plan, head, "brain", 0.2, 0.08, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.9, "digestion_meat": 0.8, "digestion_plant": 0.1, "endothermy": 0.0,
		"thermal_optimum": 20.0, "water_retention": 0.2, "clutch_size": 12.0, "offspring_investment": 0.02,
		"parental_care": 0.05, "sociality": 0.2, "activity_phase": 0.6})


static func _turtle() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Панцирная черепаха"
	plan.coverings = [
		CoveringDef.make(&"scales", Color(0.42, 0.45, 0.25), Color(0.75, 0.7, 0.45), &"mottled"),
		CoveringDef.make(&"shell", Color(0.36, 0.3, 0.16), Color(0.72, 0.6, 0.3), &"reticulated"),
	]
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "herbivore"}
	var t := plan.add_part(chain(&"torso", 0.12, [[0.15, 0.16, 0, 0, 0.6], [0.2, 0.17, 0, 0, 0.6], [0.14, 0.13, 0, 0, 0.6]]))
	att(plan, point(&"shell", {"size": 1.25, "height": 0.8, "coverage": 1.0, "shell_covering": 1}), t, 0.5, 90.0, 0.35, 0, 0, 0, 0, "Панцирь")
	var neck := att(plan, chain(&"neck", 0.05, [[0.1, 0.045, 12]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Шея")
	var head := att(plan, chain(&"head", 0.045, [[0.07, 0.05, -10], [0.04, 0.03, -10]]), neck, 1.0, 0.0, 0.0)
	att(plan, point(&"eye", {"eye_type": "camera", "size": 0.3, "fov": 150.0, "acuity": 0.5}), head, 0.6, 30.0, 0.9, 1, 0.0, 35.0)
	att(plan, point(&"mouth", {"mouth_type": "beak", "teeth": "none", "size": 0.8, "bite_force": 0.6}), head, 1.0, 270.0, 0.3)
	for spec in [[0.8, "Передняя нога", [[0.1, 0.045, 0, 10], [0.08, 0.038, 0, 20]]], [0.15, "Задняя нога", [[0.1, 0.048, 0, -10], [0.07, 0.04, 0, 25]]]]:
		var leg := chain(&"limb", 0.05, spec[2], &"walk")
		leg.set_param("foot", "claw")
		att(plan, leg, t, spec[0], 330.0, 0.75, 1, -35.0, 0.0, 0.0, spec[1])
	att(plan, chain(&"tail", 0.03, [[0.06, 0.012, -20]]), t, 0.0, 0.0, 0.0)
	organ(plan, t, "lungs", 0.6, 0.12, 90.0, 0.3)
	organ(plan, t, "heart", 0.7, 0.03, 270.0, 0.2)
	organ(plan, t, "gut", 0.4, 0.15, 270.0, 0.2)
	organ(plan, t, "gonads", 0.15, 0.03, 270.0, 0.3)
	organ(plan, head, "brain", 0.3, 0.06, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.1, "digestion_plant": 0.8, "endothermy": 0.0, "thermal_optimum": 26.0,
		"lifespan": 2.0, "maturity_age": 1.6, "armor": 1.3, "clutch_size": 8.0, "offspring_investment": 0.03,
		"parental_care": 0.0, "sociality": 0.1, "boldness": 0.7, "metabolism": 0.7})


static func _worm() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Кольчатый червь"
	plan.coverings = [CoveringDef.make(&"slime", Color(0.72, 0.42, 0.42), Color(0.55, 0.3, 0.32), &"rings")]
	plan.biology = {"habitat": "land", "reproduction_mode": "hermaphrodite", "reproduction_method": "eggs", "diet": "detritivore"}
	var segs := []
	for i in 10:
		segs.append([0.05, 0.022 - 0.006 * absf(float(i) - 5.0) / 5.0, 0, 0])
	var t := plan.add_part(_set_muscle(chain(&"torso", 0.015, segs), 0.55, 0.2))
	att(plan, point(&"mouth", {"mouth_type": "sucker", "teeth": "none", "size": 0.5, "bite_force": 0.1}), t, 1.0, 0.0, 0.0)
	att(plan, point(&"sensor", {"sensor_type": "vibration", "sensitivity": 0.8, "size": 0.2}), t, 0.95, 90.0, 0.9)
	att(plan, point(&"eye", {"eye_type": "ocellus", "size": 0.15, "fov": 180.0, "acuity": 0.05}), t, 0.97, 60.0, 0.9, 1)
	organ(plan, t, "gut", 0.5, 0.3, 90.0, 0.0)
	organ(plan, t, "gonads", 0.8, 0.04, 270.0, 0.3)
	return _finish(plan, {"diet_preference": 0.05, "digestion_plant": 0.7, "digestion_carrion": 0.4, "endothermy": 0.0,
		"thermal_optimum": 14.0, "water_retention": 0.15, "sociality": 0.1, "boldness": 0.2, "clutch_size": 6.0,
		"offspring_investment": 0.03, "lifespan": 0.8, "parental_care": 0.0, "activity_phase": 0.8})


static func _centipede() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Многоножка"
	plan.coverings = [CoveringDef.make(&"chitin", Color(0.55, 0.18, 0.08), Color(0.95, 0.6, 0.15), &"bands")]
	plan.coverings[0].iridescence = 0.2
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "carnivore"}
	var segs := []
	for i in 12:
		segs.append([0.045, 0.026, 0, 0, 0.6])
	var t := plan.add_part(chain(&"torso", 0.022, segs))
	var head := att(plan, chain(&"head", 0.025, [[0.03, 0.022, 0, 0, 0.6]]), t, 1.0, 0.0, 0.0)
	att(plan, chain(&"antenna", 0.004, [[0.05, 0.003, 15, 30], [0.05, 0.002, 5, 10]]), head, 0.9, 60.0, 0.9, 1, 0, 0, 0, "Усик")
	att(plan, point(&"mouth", {"mouth_type": "mandibles", "teeth": "fangs", "venom": 0.6, "size": 0.9, "bite_force": 0.6}), head, 1.0, 270.0, 0.3)
	att(plan, point(&"eye", {"eye_type": "simple", "size": 0.2, "acuity": 0.2}), head, 0.5, 40.0, 0.95, 1)
	var leg := chain(&"limb", 0.006, [[0.035, 0.005, 25, 0], [0.04, 0.003, -60, -10]], &"walk")
	leg.set_param("foot", "claw")
	leg.repeat_count = 11
	leg.repeat_span = 0.88
	leg.repeat_yaw = 40.0
	att(plan, leg, t, 0.04, 340.0, 0.9, 1, -10.0, 0.0, 0.0, "Нога")
	organ(plan, t, "trachea", 0.5, 0.08, 90.0, 0.3)
	organ(plan, t, "gut", 0.5, 0.2, 270.0, 0.0)
	organ(plan, t, "gonads", 0.2, 0.03, 270.0, 0.3)
	organ(plan, t, "venom_gland", 0.97, 0.02, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.95, "digestion_meat": 0.85, "digestion_plant": 0.05, "endothermy": 0.0,
		"aggression": 0.6, "boldness": 0.6, "sociality": 0.05, "activity_phase": 0.9, "clutch_size": 8.0,
		"offspring_investment": 0.03, "armor": 1.1})


static func _insect() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Изумрудный жук"
	plan.coverings = [
		CoveringDef.make(&"chitin", Color(0.1, 0.4, 0.25), Color(0.05, 0.15, 0.1), &"gradient"),
		CoveringDef.make(&"membrane", Color(0.85, 0.9, 0.95), Color(0.6, 0.7, 0.8), &"reticulated"),
	]
	plan.coverings[0].iridescence = 0.8
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "herbivore", "molting": true}
	var t := plan.add_part(_set_muscle(chain(&"torso", 0.008, [[0.035, 0.018, 0], [0.03, 0.016, 0], [0.008, 0.007, 0], [0.03, 0.014, 0]]), 0.55, 0.9))
	var head := att(plan, chain(&"head", 0.012, [[0.02, 0.013, -10]]), t, 1.0, 0.0, 0.0)
	att(plan, point(&"eye", {"eye_type": "compound", "size": 0.6, "fov": 200.0, "acuity": 0.4, "color_vision": 0.8}), head, 0.55, 30.0, 0.9, 1, 0.0, 25.0, 0.0, "Фасеточный глаз")
	att(plan, chain(&"antenna", 0.0016, [[0.03, 0.0013, 25, 35], [0.03, 0.001, 10, 5]]), head, 0.92, 65.0, 0.9, 1, 0, 0, 0, "Усик")
	att(plan, point(&"mouth", {"mouth_type": "mandibles", "teeth": "grinding", "size": 0.8}), head, 1.0, 270.0, 0.3)
	var leg := chain(&"limb", 0.004, [[0.03, 0.0035, 40, 0], [0.04, 0.0025, -80, 0], [0.018, 0.0018, -10, 0]], &"walk")
	leg.set_param("foot", "claw")
	leg.repeat_count = 3
	leg.repeat_span = 0.22
	leg.repeat_yaw = 80.0
	att(plan, leg, t, 0.75, 300.0, 0.85, 1, 0.0, 0.0, 0.0, "Нога")
	var wing := _set_muscle(chain(&"wing", 0.003, [[0.11, 0.002, 0, -62]], &"fly"), 0.7, 0.9)
	wing.set_param("wing_type", "insect")
	wing.set_param("chord", 0.9)
	wing.covering = 1
	wing.repeat_count = 2
	wing.repeat_span = -0.1
	att(plan, wing, t, 0.92, 72.0, 0.9, 1, -30.0, 0.0, 0.0, "Крыло")
	organ(plan, t, "trachea", 0.6, 0.12, 90.0, 0.3)
	organ(plan, t, "gut", 0.3, 0.2, 270.0, 0.2)
	organ(plan, t, "gonads", 0.15, 0.06, 270.0, 0.3)
	return _finish(plan, {"diet_preference": 0.1, "digestion_plant": 0.8, "endothermy": 0.0, "thermal_optimum": 24.0,
		"sociality": 0.3, "clutch_size": 12.0, "offspring_investment": 0.02, "lifespan": 0.7, "maturity_age": 0.7,
		"parental_care": 0.0, "water_retention": 0.85})


static func _spider() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Охотник-паук"
	plan.coverings = [
		CoveringDef.make(&"chitin", Color(0.18, 0.14, 0.12), Color(0.85, 0.55, 0.15), &"spots"),
		CoveringDef.make(&"bristles", Color(0.3, 0.24, 0.18), Color(0.6, 0.5, 0.35), &"bands"),
	]
	plan.biology = {"habitat": "land", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "carnivore"}
	var t := plan.add_part(chain(&"torso", 0.012, [[0.05, 0.034, 6], [0.012, 0.01, -6], [0.035, 0.022, 0, 0, 0.8]]))
	var leg := chain(&"limb", 0.005, [[0.045, 0.0045, 50, 0], [0.055, 0.0035, -70, 0], [0.045, 0.0022, -30, 0]], &"walk")
	leg.set_param("foot", "claw")
	leg.repeat_count = 4
	leg.repeat_span = 0.16
	leg.repeat_yaw = 110.0
	leg.covering = 1
	att(plan, leg, t, 0.82, 320.0, 0.85, 1, 0.0, 0.0, 0.0, "Нога")
	att(plan, point(&"eye", {"eye_type": "camera", "size": 0.32, "fov": 60.0, "acuity": 0.7, "iris_color": Color(0.05, 0.05, 0.05)}), t, 0.985, 72.0, 0.85, 1, 0.0, 40.0, 0.0, "Главный глаз")
	att(plan, point(&"eye", {"eye_type": "simple", "size": 0.2, "fov": 180.0, "acuity": 0.3}), t, 0.95, 50.0, 0.95, 1, 0.0, 10.0, 0.0, "Боковой глаз")
	att(plan, point(&"mouth", {"mouth_type": "mandibles", "teeth": "fangs", "venom": 0.8, "size": 0.7, "bite_force": 0.5}), t, 1.0, 270.0, 0.35, 0, 0, 0, 0, "Хелицеры")
	att(plan, point(&"gland", {"gland_type": "silk", "strength": 0.7}), t, 0.02, 270.0, 0.8)
	organ(plan, t, "lungs", 0.4, 0.06, 270.0, 0.4)
	organ(plan, t, "heart", 0.3, 0.02, 90.0, 0.4)
	organ(plan, t, "gut", 0.25, 0.15, 270.0, 0.2)
	organ(plan, t, "venom_gland", 0.92, 0.04, 90.0, 0.3)
	return _finish(plan, {"diet_preference": 1.0, "digestion_meat": 0.9, "digestion_plant": 0.0, "endothermy": 0.0,
		"aggression": 0.6, "boldness": 0.5, "sociality": 0.0, "territoriality": 0.6, "activity_phase": 0.85,
		"clutch_size": 12.0, "offspring_investment": 0.02, "vigilance": 0.6})


static func _octopus() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Умный осьминог"
	plan.body_axis = &"vertical"
	plan.coverings = [
		CoveringDef.make(&"skin", Color(0.75, 0.32, 0.22), Color(0.95, 0.65, 0.5), &"mottled"),
		CoveringDef.make(&"skin", Color(0.9, 0.62, 0.55), Color(0.98, 0.85, 0.8), &"none"),
	]
	plan.coverings[0].roughness_bias = -0.25
	plan.biology = {"habitat": "water", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "carnivore"}
	var t := plan.add_part(_set_muscle(chain(&"torso", 0.08, [[0.08, 0.11], [0.12, 0.1], [0.08, 0.04]]), 0.6, 0.6))
	var arm := _set_muscle(chain(&"tentacle", 0.035, [[0.12, 0.028, 0, -12], [0.12, 0.02, 0, -18], [0.11, 0.013, 0, -14], [0.1, 0.006, 0, -10]], &"grasp"), 0.75, 0.5)
	arm.covering = 1
	arm.symmetry = 8
	att(plan, arm, t, 0.0, 0.0, 0.55, 8, 0.0, 0.0, 0.0, "Щупальце")
	att(plan, point(&"eye", {"eye_type": "camera", "size": 0.32, "fov": 180.0, "acuity": 0.85, "night_vision": 0.6, "pupil": "horizontal", "iris_color": Color(0.85, 0.7, 0.3)}), t, 0.25, 300.0, 0.95, 1, 0.0, 0.0, 0.0, "Глаз")
	att(plan, point(&"mouth", {"mouth_type": "beak", "teeth": "none", "size": 0.4, "bite_force": 0.7, "venom": 0.3}), t, 0.0, 0.0, 0.0)
	att(plan, point(&"gill", {"area": 1.5, "slits": 2}), t, 0.4, 0.0, 0.7, 1)
	att(plan, point(&"gland", {"gland_type": "ink", "strength": 0.8}), t, 0.35, 90.0, 0.5)
	organ(plan, t, "brain", 0.25, 0.08, 90.0, 0.3)
	organ(plan, t, "heart", 0.5, 0.03, 90.0, 0.3)
	organ(plan, t, "gut", 0.6, 0.12, 90.0, 0.2)
	organ(plan, t, "gonads", 0.75, 0.05, 90.0, 0.2)
	return _finish(plan, {"diet_preference": 0.95, "digestion_meat": 0.9, "digestion_plant": 0.0, "endothermy": 0.0,
		"thermal_optimum": 14.0, "learning": 0.95, "curiosity": 0.9, "sociality": 0.05, "boldness": 0.5,
		"clutch_size": 12.0, "offspring_investment": 0.01, "parental_care": 0.6, "lifespan": 0.6})


static func _jellyfish() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Светящаяся медуза"
	plan.body_axis = &"vertical"
	plan.coverings = [
		CoveringDef.make(&"membrane", Color(0.85, 0.55, 0.85), Color(0.6, 0.9, 1.0), &"gradient"),
		CoveringDef.make(&"membrane", Color(0.95, 0.7, 0.9), Color(0.7, 0.95, 1.0), &"none"),
	]
	plan.biology = {"habitat": "water", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "filter"}
	var t := plan.add_part(_set_muscle(chain(&"torso", 0.14, [[0.05, 0.19], [0.08, 0.17], [0.07, 0.11], [0.03, 0.03]]), 0.3, 0.3))
	var tent := chain(&"tentacle", 0.008, [[0.14, 0.007, 0, -4], [0.14, 0.005, 0, 4], [0.14, 0.004, 0, -4], [0.12, 0.002, 0, 3]], &"attack")
	tent.covering = 1
	tent.set_param("suckers", false)
	att(plan, tent, t, 0.06, 0.0, 0.95, 12, 0.0, -82.0, 0.0, "Стрекательное щупальце")
	var oral := chain(&"tentacle", 0.03, [[0.1, 0.022, 0, -6, 0.35], [0.1, 0.012, 0, -4, 0.35]], &"grasp")
	oral.covering = 1
	att(plan, oral, t, 0.0, 0.0, 0.25, 4, 0.0, 0.0, 0.0, "Ротовая лопасть")
	att(plan, point(&"eye", {"eye_type": "ocellus", "size": 0.12, "fov": 180.0, "acuity": 0.05}), t, 0.07, 15.0, 1.0, 8)
	att(plan, point(&"light_organ", {"color": Color(0.5, 0.95, 1.0), "intensity": 0.8, "size": 0.12}), t, 0.3, 37.0, 1.0, 8)
	att(plan, point(&"mouth", {"mouth_type": "filter", "teeth": "none", "size": 0.5, "bite_force": 0.0}), t, 0.0, 0.0, 0.0)
	organ(plan, t, "gut", 0.3, 0.2, 0.0, 0.0)
	organ(plan, t, "gonads", 0.4, 0.05, 90.0, 0.5)
	return _finish(plan, {"diet_preference": 0.6, "digestion_meat": 0.6, "digestion_plant": 0.5, "endothermy": 0.0,
		"thermal_optimum": 18.0, "sociality": 0.6, "boldness": 0.8, "clutch_size": 12.0, "offspring_investment": 0.02,
		"parental_care": 0.0, "lifespan": 0.6, "metabolism": 0.6})


static func _starfish() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Морская звезда"
	plan.body_axis = &"vertical"
	plan.coverings = [CoveringDef.make(&"plates", Color(0.92, 0.42, 0.15), Color(0.98, 0.75, 0.35), &"spots")]
	plan.biology = {"habitat": "water", "reproduction_mode": "sexual", "reproduction_method": "eggs", "diet": "carnivore"}
	var t := plan.add_part(chain(&"torso", 0.075, [[0.025, 0.07], [0.015, 0.04]]))
	var arm := chain(&"tentacle", 0.05, [[0.08, 0.034, 0, 2, 0.5, 90], [0.08, 0.02, 0, 2, 0.5], [0.05, 0.008, 0, 1, 0.5]], &"none")
	arm.set_param("suckers", true)
	var arm_id := att(plan, arm, t, 0.3, 90.0, 0.85, 5, 0.0, -10.0, 0.0, "Луч")
	att(plan, point(&"eye", {"eye_type": "ocellus", "size": 0.5, "acuity": 0.05, "fov": 160.0}), arm_id, 1.0, 0.0, 0.0)
	att(plan, point(&"mouth", {"mouth_type": "sucker", "teeth": "none", "size": 0.5}), t, 0.0, 0.0, 0.0)
	organ(plan, t, "gut", 0.5, 0.25, 0.0, 0.0)
	organ(plan, t, "gonads", 0.5, 0.05, 90.0, 0.5)
	return _finish(plan, {"diet_preference": 0.8, "digestion_meat": 0.7, "digestion_carrion": 0.5, "endothermy": 0.0,
		"regeneration": 0.95, "thermal_optimum": 12.0, "sociality": 0.2, "clutch_size": 12.0, "offspring_investment": 0.01,
		"parental_care": 0.0, "metabolism": 0.6, "lifespan": 1.4})


static func _cell() -> Genome:
	var plan := BodyPlan.new()
	plan.name = "Гигантская клетка"
	plan.coverings = [
		CoveringDef.make(&"membrane", Color(0.45, 0.8, 0.5), Color(0.85, 1.0, 0.7), &"mottled"),
		CoveringDef.make(&"membrane", Color(0.6, 0.85, 0.6), Color(0.9, 1.0, 0.85), &"none"),
	]
	plan.biology = {"habitat": "water", "reproduction_mode": "asexual", "reproduction_method": "fission", "diet": "photosynth"}
	var cell := chain(&"cell", 0.045, [[0.06, 0.04, 0, 0, 0.9]])
	cell.set_param("organelles", 9)
	var c := plan.add_part(cell)
	var flag := chain(&"flagellum", 0.004, [[0.03, 0.003, 18], [0.03, 0.0025, -30], [0.03, 0.002, 30], [0.03, 0.0015, -25]], &"swim")
	flag.covering = 1
	att(plan, flag, c, 0.0, 0.0, 0.0, 0, 0, 0, 0, "Жгутик")
	att(plan, point(&"eye", {"eye_type": "ocellus", "size": 0.15, "fov": 160.0, "acuity": 0.02, "iris_color": Color(0.9, 0.15, 0.1)}), c, 0.85, 60.0, 0.9)
	att(plan, point(&"mouth", {"mouth_type": "cell_mouth", "teeth": "none", "size": 0.3, "bite_force": 0.0}), c, 1.0, 0.0, 0.6)
	organ(plan, c, "photo_tissue", 0.5, 0.2, 90.0, 0.4)
	return _finish(plan, {"photosynthesis": 0.8, "diet_preference": 0.2, "digestion_plant": 0.5, "digestion_meat": 0.3,
		"endothermy": 0.0, "thermal_optimum": 22.0, "sociality": 0.4, "clutch_size": 2.0, "offspring_investment": 0.4,
		"lifespan": 0.5, "maturity_age": 0.5, "parental_care": 0.0, "boldness": 0.6})
