class_name PhysiologyNotes
extends RefCounted
## Explanatory physiological diagnostics (Russian, with numbers) for the
## editor's anatomical check and the procedural fauna validator. Never
## forbids a design: it explains consequences. Items: {level, system, text}.

const DIET_LABELS := {
	&"herbivore": "растительноядный", &"carnivore": "хищный", &"omnivore": "всеядный",
	&"scavenger": "падальщик", &"detritivore": "детритофаг", &"filter": "фильтратор",
	&"parasite": "паразит", &"photosynth": "фотосинтетик",
}
const RESP_LABELS := {
	&"lungs": "лёгкие", &"gills": "жабры", &"trachea": "трахеи", &"cutaneous": "кожное дыхание",
	&"mixed": "смешанное (несколько органов)", &"none": "нет органов газообмена",
}
const DAY := Units.SECONDS_PER_DAY


static func _item(level: StringName, text: String) -> Dictionary:
	return {"level": level, "system": &"physiology", "text": text}


static func build(p: PhysiologyProfile) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_metabolism(p, out)
	_respiration(p, out)
	_thermal(p, out)
	_water(p, out)
	_diet(p, out)
	_life(p, out)
	if p.free_energy_w > 0.0:
		out.append(_item(&"info", "Фантастическое правило: %.1f Вт энергии из неизвестного источника." % p.free_energy_w))
	return out


static func _metabolism(p: PhysiologyProfile, out: Array[Dictionary]) -> void:
	var daily := p.bmr_watts * DAY / 1.0e6
	var kind := "теплокровный" if p.endothermy > 0.7 else ("холоднокровный" if p.endothermy < 0.3 else "частично теплокровный")
	out.append(_item(&"info", "Обмен покоя %s Вт (%.2f МДж/сут), %s организм (теплокровность %d%%)." % [_num(p.bmr_watts), daily, kind, int(p.endothermy * 100.0)]))
	if p.mass > 80.0:
		out.append(_item(&"info", "Большая масса тела повышает энергетические затраты: %.0f кг требуют %.1f МДж в сутки только на поддержание жизни." % [p.mass, daily * (1.0 + p.upkeep_frac)]))
	var fast := p.max_energy / maxf(p.maintenance_rate(p.body_temp_set) * 2.0, 1e-9) / DAY
	var level := &"warning" if fast < 0.4 else &"info"
	out.append(_item(level, "Запас энергии %s — хватит примерно на %.1f сут при обычной активности без еды." % [_energy(p.max_energy), fast]))


static func _respiration(p: PhysiologyProfile, out: Array[Dictionary]) -> void:
	if p.ignore_oxygen:
		out.append(_item(&"info", "Особое правило: организм не нуждается в кислороде."))
		return
	var habitat := p.habitat
	out.append(_item(&"info", "Дыхание: %s. Запас аэробной мощности: на суше ×%.1f, под водой ×%.1f от обмена покоя." % [RESP_LABELS.get(p.respiration, str(p.respiration)), p.scope_land, p.scope_water]))
	var land_bad := p.scope_land < 1.0
	var water_bad := p.scope_water < 1.0 and not (p.lungs_w > 0.0 and p.can_swim)
	if (habitat == &"land" and land_bad) or (habitat == &"water" and water_bad) or (habitat == &"amphibious" and land_bad and water_bad):
		var media := {&"land": "суши", &"water": "воды", &"amphibious": "суши и воды"}
		var medium := str(media.get(habitat, "среды"))
		out.append(_item(&"critical", "Отсутствует эффективная система газообмена для выбранной среды (%s): органы дыхания покрывают лишь %d%% потребности покоя." % [medium, int(minf(p.scope_land if habitat != &"water" else p.scope_water, 9.99) * 100.0)]))
	elif habitat == &"amphibious" and (land_bad or water_bad):
		out.append(_item(&"warning", "Земноводному не хватает газообмена %s — эта среда доступна лишь на время." % ("на суше" if land_bad else "под водой")))
	if p.trachea_w > 0.0 and p.trachea_efficiency < 0.6:
		var lvl := &"warning" if p.scope_land >= 1.0 else &"critical"
		out.append(_item(lvl, "Трахейное дыхание неэффективно для такой массы: при толщине тела %.1f см диффузия даёт лишь %d%% эффективности (%.0f г)." % [p.body_radius * 200.0, int(p.trachea_efficiency * 100.0), p.mass * 1000.0]))
	elif habitat != &"water" and p.scope_land >= 1.0 and p.scope_land < 2.0:
		out.append(_item(&"warning", "Газообмен на пределе: запас аэробной мощности всего ×%.1f — высокая активность быстро утомляет." % p.scope_land))
	if p.respiration == &"cutaneous" and p.mass > 2.0 and maxf(p.scope_land, p.scope_water) < 3.0:
		out.append(_item(&"warning", "Кожное дыхание при массе %.1f кг: площадь поверхности мала относительно объёма (%.0f м²/м³)." % [p.mass, p.surface_to_volume]))
	if p.moist_skin_fraction > 0.4 and p.skin_air_w > 0.2 * (p.lungs_w + p.trachea_w + p.skin_air_w):
		out.append(_item(&"info", "Кожное дыхание требует влажной кожи: в сухом воздухе газообмен падает."))
	if p.gills_w > 0.0 and p.lungs_w <= 0.0 and habitat != &"water":
		out.append(_item(&"warning", "Жабры работают только в воде: на суше организм задохнётся."))
	if p.lungs_w > 0.0 and p.habitat != &"land":
		var hold := p.breath_hold_s(p.maintenance_rate(p.body_temp_set) * 2.0)
		out.append(_item(&"info", "Задержка дыхания под водой ≈ %s." % _duration(hold)))


static func _thermal(p: PhysiologyProfile, out: Array[Dictionary]) -> void:
	var r := ThermalModel.Result.new()
	var heat := p.maintenance_rate(p.body_temp_set)
	if p.endothermy >= 0.5:
		# Lower critical temperature: metabolic heat balances loss at the set point.
		var lct := p.body_temp_set - heat / maxf(p.conductance_air, 1e-6)
		ThermalModel.steady(p, -10.0, false, 0.0, 2.0, heat, 1.0, r)
		var extra := r.extra_w / maxf(heat, 1e-9) * 100.0
		out.append(_item(&"info", "Термонейтральная зона начинается от %.0f °C; при −10 °C обогрев требует +%d%% энергии (теплоизоляция покрова %.2f)." % [lct, int(extra), p.insulation]))
		if r.cold_stress > 0.3:
			out.append(_item(&"warning", "При −10 °C теплопродукции не хватает: организм переохлаждается (тело %.0f °C)." % r.body_temp))
		ThermalModel.steady(p, 35.0, false, 1.0, 1.0, heat, 1.0, r)
		if r.heat_stress > 0.2:
			out.append(_item(&"warning", "Перегрев в жару: при 35 °C на солнце тело нагревается до %.0f °C — плотный покров мешает теплоотдаче." % r.body_temp))
	else:
		out.append(_item(&"info", "Холоднокровный: скорость и активность зависят от температуры тела (оптимум %.0f °C, допуск ±%.0f °C)." % [p.thermal_optimum, p.thermal_tolerance]))


static func _water(p: PhysiologyProfile, out: Array[Dictionary]) -> void:
	if p.habitat == &"water":
		return
	var heat := p.maintenance_rate(p.body_temp_set) * 2.0
	var loss := p.water_loss_rate(25.0, 0.3, false, heat) * DAY
	var frac := loss / maxf(p.body_water_kg, 1e-9)
	if frac > 0.6:
		out.append(_item(&"warning", "Покров плохо удерживает воду: в сухом воздухе теряется %d%% воды тела в сутки — нужна влажная среда." % int(frac * 100.0)))
	elif frac > 0.25:
		out.append(_item(&"info", "Потеря воды в сухом воздухе ≈ %d%% воды тела в сутки." % int(frac * 100.0)))


static func _diet(p: PhysiologyProfile, out: Array[Dictionary]) -> void:
	var e := p.diet_eff
	out.append(_item(&"info", "Пищеварение: растения %d%%, мясо %d%%, падаль %d%%, детрит %d%%, фильтрация %d%% — %s." % [
		int(float(e["plant"]) * 100.0), int(float(e["meat"]) * 100.0), int(float(e["carrion"]) * 100.0),
		int(float(e["detritus"]) * 100.0), int(float(e["filter"]) * 100.0), DIET_LABELS.get(p.diet, str(p.diet))]))
	var best := 0.0
	for k in ["plant", "meat", "carrion", "detritus", "filter"]:
		best = maxf(best, float(e[k]))
	if best < 0.15 and float(e["photo"]) < 0.2 and p.free_energy_w <= 0.0:
		out.append(_item(&"critical", "Организм не может эффективно усваивать никакую пищу: нет подходящего ротового аппарата или пищеварительных органов."))
	elif p.declared_diet != p.diet and DIET_LABELS.has(p.declared_diet):
		var main := {&"herbivore": "plant", &"carnivore": "meat", &"scavenger": "carrion", &"detritivore": "detritus",
			&"filter": "filter", &"photosynth": "photo", &"parasite": "meat"}
		var key := str(main.get(p.declared_diet, "plant"))
		var declared_eff := maxf(float(e["plant"]), float(e["meat"])) if p.declared_diet == &"omnivore" else float(e[key])
		var compatible := declared_eff >= 0.25 or p.diet == &"omnivore"
		out.append(_item(&"info" if compatible else &"warning", "Строение рта и кишечника соответствует рациону «%s», а заявлен «%s»." % [DIET_LABELS[p.diet], DIET_LABELS[p.declared_diet]]))


static func _life(p: PhysiologyProfile, out: Array[Dictionary]) -> void:
	var dev := LifeHistory.development_time(p) / DAY
	out.append(_item(&"info", "Созревание за %.1f сут, продолжительность жизни ≈ %.0f сут; потомство: %.0f × %d%% массы родителя, развитие %.1f сут." % [
		p.maturity_age / DAY, p.lifespan / DAY, p.clutch, int(p.offspring_fraction * 100.0), dev]))
	var prep := maxf(p.gestation_s, p.egg_formation_s)
	if prep > p.maturity_age * 0.5:
		out.append(_item(&"info", "Медленное размножение: подготовка выводка занимает %.1f сут — продуктивность ограничена %s." % [prep / DAY, "газообменом" if p.production_w < p.max_assimilation_w else "пищеварением"]))
	var cost := LifeHistory.offspring_cost(p) * p.clutch
	var reserves := cost / maxf(p.max_energy, 1e-9)
	if reserves > 1.5:
		out.append(_item(&"info", "Размножение затратно: один выводок стоит %.1f полных запаса энергии (%.0f суточных норм обмена) — нужно обильное питание." % [reserves, cost / maxf(p.bmr_watts * DAY, 1e-9)]))


static func _num(w: float) -> String:
	return "%.0f" % w if w >= 10.0 else ("%.2f" % w if w >= 0.1 else "%.3f" % w)


static func _energy(j: float) -> String:
	if j >= 1.0e6:
		return "%.1f МДж" % (j / 1.0e6)
	return "%.0f кДж" % (j / 1.0e3)


static func _duration(s: float) -> String:
	if s >= 3600.0:
		return "%.1f ч" % (s / 3600.0)
	if s >= 60.0:
		return "%.0f мин" % (s / 60.0)
	return "%.0f с" % s
