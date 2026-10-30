class_name PanelSpec
extends RefCounted
## Describes the context panel of a selected part as data, generated from
## PartSchema (so a new part kind or parameter appears in the editor without
## UI code). PartPanel turns these specs into widgets.
##
## Item: {key, target, type, label, min, max, step, options, unit, factor,
##        exp (exponential slider), hint}
##   target: &"param"   part.params[key] (PartSchema)
##           &"part"    a BodyPart field (attach_t, yaw, scale, symmetry...)
##           &"chain"   an aggregate of the segment chain (EditorCommands)
##           &"segment" a BodySegment field (per-segment editors)
##   type:   "float" | "int" | "bool" | "enum" | "color" | "text" | "symmetry"
## Sections: sections_for(part, is_root) → [{id, title, icon, items}]

## Kinds that have a locomotor/behavioural function choice.
const FUNCTION_KINDS: Array[StringName] = [&"limb", &"fin", &"wing", &"tentacle", &"antenna", &"flagellum", &"tail"]
## Point kinds whose orientation is a gaze/hearing direction.
const DIRECTED_KINDS: Array[StringName] = [&"eye", &"ear", &"nose", &"sensor", &"light_organ", &"whisker", &"mouth"]


static func item(key: String, target: StringName, type: String, label: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"key": key, "target": target, "type": type, "label": label}
	for k in extra:
		d[k] = extra[k]
	return d


## Exactly the PartSchema parameters of `kind` (order preserved).
static func params_for(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var specs := PartSchema.param_specs(kind)
	for key in specs:
		var s: Dictionary = specs[key]
		var it := item(str(key), &"param", str(s.get("type", "float")), str(s.get("label", key)))
		for f in ["min", "max", "step", "hint", "default"]:
			if s.has(f):
				it[f] = s[f]
		if s.has("options"):
			var opts: Array = s["options"]
			it["options"] = opts.duplicate()
		if it["type"] == "int" and not it.has("step"):
			it["step"] = 1
		out.append(it)
	return out


## Whole-chain shape controls of spine kinds (empty for point kinds).
static func chain_for(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not PartSchema.is_spine(kind):
		return out
	out.append(item("segment_count", &"chain", "int", "Сегменты", {"min": 1, "max": 32, "step": 1}))
	out.append(item("length", &"chain", "float", "Длина", {"min": 0.002, "max": 8.0, "step": 0.001, "unit": "см", "factor": 100.0, "exp": true}))
	out.append(item("thickness", &"chain", "float", "Толщина", {"min": 0.0005, "max": 3.0, "step": 0.0005, "unit": "см", "factor": 100.0, "exp": true}))
	out.append(item("taper", &"chain", "float", "Сужение к концу", {"min": 0.05, "max": 2.0, "step": 0.05, "unit": "×", "hint": "Радиус конца относительно основания"}))
	if kind != &"torso" and kind != &"cell":
		out.append(item("bend", &"chain", "float", "Изгиб цепи", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
	out.append(item("mobility", &"chain", "float", "Подвижность суставов", {"min": 0.0, "max": 120.0, "step": 1.0, "unit": "°", "hint": "Размах движения в суставах"}))
	out.append(item("stiffness", &"chain", "float", "Жёсткость", {"min": 0.0, "max": 1.0, "step": 0.05}))
	if FUNCTION_KINDS.has(kind):
		var opts: Array = []
		for f in PartSchema.FUNCTIONS:
			opts.append(str(f))
		out.append(item("function", &"part", "enum", "Функция", {"options": opts, "labels": PartSchema.FUNCTION_LABELS}))
	return out


## Muscle controls of spine kinds.
static func muscle_for(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not PartSchema.is_spine(kind):
		return out
	out.append(item("muscle_ratio", &"part", "float", "Доля мышц", {"min": 0.0, "max": 0.9, "step": 0.01, "unit": "%", "factor": 100.0, "hint": "Больше силы и массы, выше расход энергии"}))
	out.append(item("fast_twitch", &"part", "float", "Быстрые волокна", {"min": 0.0, "max": 1.0, "step": 0.05, "unit": "%", "factor": 100.0, "hint": "Быстрые — мощность и рывок, медленные — выносливость"}))
	return out


## Gaze/orientation controls of sense organs (yaw/pitch in the attach frame).
static func direction_for(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DIRECTED_KINDS.has(kind):
		return out
	out.append(item("yaw", &"part", "float", "Направление: вперёд/назад", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
	out.append(item("pitch", &"part", "float", "Направление: вверх/вниз", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
	return out


## Common attachment controls. The root part has no parent: only scale,
## covering, label and lock apply.
static func attachment_for(kind: StringName, is_root: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_root:
		out.append(item("attach_t", &"part", "float", "Положение вдоль родителя", {"min": 0.0, "max": 1.0, "step": 0.01, "unit": "%", "factor": 100.0}))
		out.append(item("attach_angle", &"part", "float", "Угол вокруг оси", {"min": 0.0, "max": 360.0, "step": 1.0, "unit": "°", "hint": "0 — справа, 90 — спина, 180 — слева, 270 — брюхо"}))
		out.append(item("attach_depth", &"part", "float", "Глубина", {"min": 0.0, "max": 1.5, "step": 0.01, "hint": "0 — на оси, 1 — на поверхности, меньше 1 — внутри"}))
		if not DIRECTED_KINDS.has(kind):
			out.append(item("yaw", &"part", "float", "Поворот (рыскание)", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
			out.append(item("pitch", &"part", "float", "Наклон (тангаж)", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
		out.append(item("roll", &"part", "float", "Крен", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
	out.append(item("scale", &"part", "float", "Масштаб части", {"min": 0.1, "max": 5.0, "step": 0.01, "unit": "×", "exp": true}))
	if not is_root:
		out.append(item("symmetry", &"part", "symmetry", "Симметрия"))
		out.append(item("repeat_count", &"part", "int", "Повторы (метамерия)", {"min": 1, "max": 32, "step": 1}))
		out.append(item("repeat_span", &"part", "float", "Размах повторов", {"min": -1.0, "max": 1.0, "step": 0.01, "hint": "Доля длины родителя, на которую распределяются копии"}))
		out.append(item("repeat_yaw", &"part", "float", "Веер повторов", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}))
	out.append(item("covering", &"part", "int", "Слот покрова", {"min": 0, "max": CoveringDef.MAX_SLOTS - 1, "step": 1}))
	out.append(item("label", &"part", "text", "Подпись"))
	out.append(item("locked", &"part", "bool", "Заблокировать"))
	return out


## Per-segment controls (Shape / Anatomy modes).
static func segment_items(with_joints: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		item("length", &"segment", "float", "Длина", {"min": 0.002, "max": 5.0, "step": 0.001, "unit": "см", "factor": 100.0, "exp": true}),
		item("radius", &"segment", "float", "Радиус конца", {"min": 0.0005, "max": 3.0, "step": 0.0005, "unit": "см", "factor": 100.0, "exp": true}),
		item("flatten", &"segment", "float", "Сплющенность", {"min": 0.1, "max": 4.0, "step": 0.05, "unit": "×", "hint": "Высота сечения / ширина"}),
		item("pitch", &"segment", "float", "Изгиб вверх/вниз", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}),
		item("yaw", &"segment", "float", "Изгиб вбок", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}),
		item("roll", &"segment", "float", "Скручивание", {"min": -180.0, "max": 180.0, "step": 1.0, "unit": "°"}),
	]
	if with_joints:
		out.append_array(joint_items())
	return out


static func joint_items() -> Array[Dictionary]:
	return [
		item("swing_limit", &"segment", "float", "Сустав: размах", {"min": 0.0, "max": 180.0, "step": 1.0, "unit": "°"}),
		item("twist_limit", &"segment", "float", "Сустав: скручивание", {"min": 0.0, "max": 180.0, "step": 1.0, "unit": "°"}),
		item("stiffness", &"segment", "float", "Сустав: жёсткость", {"min": 0.0, "max": 1.0, "step": 0.05}),
		item("soft", &"segment", "float", "Мягкие ткани", {"min": 0.0, "max": 1.0, "step": 0.05, "hint": "Колыхание ушей, животов, хвостов"}),
	]


## Read-only muscle group read-outs (MuscleGroup fields).
static func muscle_group_items() -> Array[Dictionary]:
	return [
		item("max_force", &"muscle", "float", "Сила", {"unit": "Н"}),
		item("speed", &"muscle", "float", "Скорость сокращения", {"unit": "дл/с"}),
		item("endurance", &"muscle", "float", "Выносливость", {"unit": "%", "factor": 100.0}),
		item("energy_cost", &"muscle", "float", "Энергозатраты", {"unit": "Вт"}),
	]


## Full context panel of a part: [{id, title, icon, items}].
static func sections_for(part: BodyPart, is_root: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := direction_for(part.kind)
	var params: Array[Dictionary] = []
	if not is_root:
		params.append_array(dir)
	params.append_array(params_for(part.kind))
	if not params.is_empty():
		out.append({"id": &"params", "title": "Параметры: " + PartSchema.label(part.kind), "icon": &"sliders", "items": params})
	var chain := chain_for(part.kind)
	if not chain.is_empty():
		out.append({"id": &"shape", "title": "Форма", "icon": &"scale", "items": chain})
	var mus := muscle_for(part.kind)
	if not mus.is_empty():
		out.append({"id": &"muscle", "title": "Мышцы", "icon": &"sprint", "items": mus})
	out.append({"id": &"attach", "title": "Крепление и копии", "icon": &"move", "items": attachment_for(part.kind, is_root)})
	return out


## Keys of all `param` items of a kind (tests compare with PartSchema).
static func param_keys(kind: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for it in params_for(kind):
		out.append(str(it["key"]))
	return out
