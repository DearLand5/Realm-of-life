class_name AnatomyDiagnostics
extends RefCounted
## Built-in "anatomical check" of a phenotype. Never forbids a design: it
## explains likely consequences. Each item: {level: &"info"|&"warning"|&"critical",
## system: StringName, text: String}. Used by the creature editor and by the
## procedural fauna generator (viability score).

const MAX_COLLISIONS := 4


static func run(ph: Phenotype) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m := ph.anatomy
	var plan := ph.genome.body_plan
	var st := m.stats
	var mass := float(st.get("mass", 0.0))
	out.append(_item(&"info", &"anatomy", "Масса %s, длина %.2f м, площадь поверхности %.2f м²." % [format_mass(mass), float(st.get("length", 0.0)), float(st.get("surface_area", 0.0))]))
	_check_collisions(ph, out)
	_check_organs(ph, out)
	_check_limbs(ph, out)
	_check_feeding(ph, out)
	_check_senses(ph, out)
	for n in ph.locomotion.notes:
		out.append(_item(n["level"], &"locomotion", n["text"]))
	var lp := ph.locomotion
	var moves := PackedStringArray()
	if lp.can_walk:
		moves.append("ходьба до %.1f м/с" % lp.run_speed)
	elif lp.can_crawl:
		moves.append("ползание %.2f м/с" % lp.crawl_speed)
	if lp.can_swim:
		moves.append("плавание %.1f м/с" % lp.swim_speed)
	if lp.can_fly:
		moves.append("полёт %.1f м/с" % lp.fly_speed)
	elif lp.can_glide:
		moves.append("планирование")
	if lp.can_climb:
		moves.append("лазание")
	if lp.can_jump:
		moves.append("прыжок %.2f м" % lp.jump_height)
	if not moves.is_empty():
		out.append(_item(&"info", &"locomotion", "Передвижение: " + ", ".join(moves) + "."))
	for n in ph.physiology.diagnose():
		out.append(n)
	if bool(plan.rule("fantasy")):
		out.append(_item(&"info", &"rules", "Вид использует фантастические биологические правила — часть ограничений ослаблена."))
	return out


## 0..1: crude viability estimate (1 = no problems).
static func viability(items: Array[Dictionary]) -> float:
	var v := 1.0
	for it in items:
		match it["level"]:
			&"warning":
				v -= 0.08
			&"critical":
				v -= 0.45
	return clampf(v, 0.0, 1.0)


static func format_mass(kg: float) -> String:
	if kg >= 1000.0:
		return "%.1f т" % (kg / 1000.0)
	if kg >= 1.0:
		return "%.1f кг" % kg
	return "%.0f г" % (kg * 1000.0)


static func _item(level: StringName, system: StringName, text: String) -> Dictionary:
	return {"level": level, "system": system, "text": text}


static func _part_name(plan: BodyPlan, id: int) -> String:
	var p := plan.get_part(id)
	if p == null:
		return "?"
	return p.label if p.label != "" else PartSchema.label(p.kind)


static func _related(m: AnatomyModel, ia: int, ib: int) -> bool:
	if ia == ib:
		return true
	var a := m.instances[ia]
	var b := m.instances[ib]
	return a.parent_instance == ib or b.parent_instance == ia or (a.parent_instance == b.parent_instance and a.part_id == b.part_id)


static func _seg_seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
	return (pts[0] - pts[1]).length()


static func _check_collisions(ph: Phenotype, out: Array[Dictionary]) -> void:
	var m := ph.anatomy
	var plan := ph.genome.body_plan
	var reported := {}
	var count := 0
	for i in m.bones.size():
		var a := m.bones[i]
		if a.part_id < 0 or a.kind in [&"torso", &"cell"]:
			continue
		for j in range(i + 1, m.bones.size()):
			var b := m.bones[j]
			if b.part_id < 0 or b.kind in [&"torso", &"cell"] or a.instance == b.instance:
				continue
			if _related(m, a.instance, b.instance):
				continue
			# Skip the first segments touching at a shared joint.
			if a.depth == 0 and b.depth == 0 and a.start.distance_to(b.start) < (a.r0 + b.r0):
				continue
			var d := _seg_seg_dist(a.start, a.end, b.start, b.end)
			var lim := (maxf(a.r0, a.r1) + maxf(b.r0, b.r1)) * 0.6
			if d < lim:
				var key := "%d-%d" % [mini(a.part_id, b.part_id), maxi(a.part_id, b.part_id)]
				if reported.has(key):
					continue
				reported[key] = true
				count += 1
				if count <= MAX_COLLISIONS:
					out.append(_item(&"warning", &"anatomy", "Части «%s» и «%s» пересекаются — это мешает движению." % [_part_name(plan, a.part_id), _part_name(plan, b.part_id)]))
	if count > MAX_COLLISIONS:
		out.append(_item(&"warning", &"anatomy", "Ещё %d пересечений частей тела." % (count - MAX_COLLISIONS)))


static func _check_organs(ph: Phenotype, out: Array[Dictionary]) -> void:
	var m := ph.anatomy
	var plan := ph.genome.body_plan
	var cavity := float(m.stats.get("cavity_volume", 0.0))
	var total := 0.0
	for v in (m.stats.get("organ_volume", {}) as Dictionary).values():
		total += float(v)
	if cavity > 0.0 and total > cavity:
		out.append(_item(&"warning", &"anatomy", "Внутренние органы не помещаются в полость тела (%d%% объёма)." % int(total / cavity * 100.0)))
	for a in m.accessories:
		if a.type != &"organ":
			continue
		if not m.primitives.is_empty() and AnatomySdf.distance(m, a.transform.origin) > 0.0:
			out.append(_item(&"warning", &"anatomy", "Орган «%s» находится вне тела." % _part_name(plan, a.part_id)))


static func _check_limbs(ph: Phenotype, out: Array[Dictionary]) -> void:
	var m := ph.anatomy
	var plan := ph.genome.body_plan
	var leg_len := float(m.stats.get("leg_length", 0.0)) / maxf(m.size_scale, 1e-6)
	var flagged := {}
	for tip in m.tips_with_function([&"walk", &"run"]):
		var b := m.bones[tip]
		if b.end.y - b.r1 > maxf(0.25 * leg_len, 0.02) and not flagged.has(b.part_id):
			flagged[b.part_id] = true
			out.append(_item(&"warning", &"locomotion", "Конечность «%s» не достаёт до земли и не участвует в опоре." % _part_name(plan, b.part_id)))
	var fly_parts := 0
	for p in plan.parts:
		if p.function == &"fly" and p.kind != &"wing":
			fly_parts += 1
	if fly_parts > 0 and float(m.stats.get("wing_area", 0.0)) <= 0.0:
		out.append(_item(&"warning", &"locomotion", "Конечности назначены для полёта, но у них нет несущей поверхности (нужны крылья)."))


static func _check_feeding(ph: Phenotype, out: Array[Dictionary]) -> void:
	var plan := ph.genome.body_plan
	var mouth: Dictionary = ph.anatomy.stats.get("mouth", {})
	var diet := str(plan.bio("diet"))
	if int(mouth.get("count", 0)) == 0 and not diet in ["photosynth", "filter", "parasite"]:
		var photo := ph.genome.value(&"photosynthesis")
		if photo < 0.2 and plan.parts_of_kind(&"cell").is_empty():
			out.append(_item(&"critical", &"physiology", "Нет ротового аппарата: организм не сможет питаться. Добавьте рот или выберите фотосинтез/фильтрацию."))
	var teeth := str(mouth.get("teeth", "none"))
	var pref := ph.genome.value(&"diet_preference")
	if pref > 0.6 and teeth in ["grinding", "none"] and str(mouth.get("type", "")) == "jaws":
		out.append(_item(&"warning", &"physiology", "Хищные предпочтения, но перетирающие зубы: охота будет малоэффективной."))
	if pref < 0.3 and teeth in ["cutting", "fangs"]:
		out.append(_item(&"info", &"physiology", "Режущие зубы у растительноядного: растительная пища усваивается хуже."))


static func _check_senses(ph: Phenotype, out: Array[Dictionary]) -> void:
	var sp := ph.senses
	if sp.eye_count == 0:
		out.append(_item(&"info", &"senses", "Нет глаз: ориентирование по запаху (%.0f м), слуху (%.0f м) и осязанию." % [sp.smell_range, sp.hearing_range]))
	elif sp.light_only:
		out.append(_item(&"info", &"senses", "Глаза различают только свет и тень."))
	else:
		out.append(_item(&"info", &"senses", "Зрение до %.0f м, поле зрения %d°." % [sp.vision_range, int(sp.vision_fov)]))
	if sp.max_range() < 6.0:
		out.append(_item(&"warning", &"senses", "Очень слабые органы чувств: организм поздно замечает еду и хищников."))
