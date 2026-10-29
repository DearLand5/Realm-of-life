class_name PartSchema
extends RefCounted
## Data-driven description of every anatomical part kind.
##
## The editor builds its context panels from PARAMS (only the parameters that
## belong to the selected kind are shown); the compiler, physiology and AI read
## the same keys. Adding a new organ type = adding an entry here plus the code
## that interprets it (see docs/ARCHITECTURE.md "Adding a part kind").
##
## Param spec fields:
##   type:  "float" | "int" | "bool" | "enum" | "color"
##   default, min, max, step (numeric), options (enum: Array[String])
##   label: UI label (ru), hint: tooltip (ru)

## Kinds with a chain of BodySegments (rendered as SDF body / tubes, own bones).
const SPINE_KINDS: Array[StringName] = [
	&"torso", &"cell", &"neck", &"head", &"tail", &"limb", &"fin", &"wing",
	&"tentacle", &"antenna", &"flagellum",
]

## Point-like parts (accessory meshes or internal organs), no segments.
const POINT_KINDS: Array[StringName] = [
	&"eye", &"ear", &"nose", &"mouth", &"horn", &"spike", &"claw", &"whisker",
	&"gill", &"sensor", &"gland", &"light_organ", &"shell", &"organ",
]

const KIND_LABELS := {
	&"torso": "Туловище", &"cell": "Клетка", &"neck": "Шея", &"head": "Голова",
	&"tail": "Хвост", &"limb": "Конечность", &"fin": "Плавник", &"wing": "Крыло",
	&"tentacle": "Щупальце", &"antenna": "Усик", &"flagellum": "Жгутик",
	&"eye": "Глаз", &"ear": "Ухо", &"nose": "Нос", &"mouth": "Рот",
	&"horn": "Рог", &"spike": "Шип", &"claw": "Коготь", &"whisker": "Вибриссы",
	&"gill": "Жабры", &"sensor": "Сенсор", &"gland": "Железа",
	&"light_organ": "Светящийся орган", &"shell": "Панцирь-раковина", &"organ": "Внутренний орган",
}

## Which editor mode owns which kinds (used to filter the part library).
const MODE_KINDS := {
	&"shape": [&"torso", &"cell", &"neck", &"head", &"tail", &"shell"],
	&"limbs": [&"limb", &"fin", &"wing", &"tentacle", &"antenna", &"flagellum"],
	&"senses": [&"eye", &"ear", &"nose", &"whisker", &"sensor", &"antenna"],
	&"organs": [&"mouth", &"horn", &"spike", &"claw", &"gill", &"gland", &"light_organ", &"organ"],
}

## Limb functions (BodyPart.function). Drive locomotion & behaviour analysis.
const FUNCTIONS: Array[StringName] = [
	&"none", &"walk", &"run", &"climb", &"swim", &"fly", &"grasp", &"dig", &"sense", &"attack",
]
const FUNCTION_LABELS := {
	&"none": "Нет", &"walk": "Ходьба", &"run": "Бег", &"climb": "Лазание",
	&"swim": "Плавание", &"fly": "Полёт", &"grasp": "Хватание", &"dig": "Рытьё",
	&"sense": "Осязание", &"attack": "Атака",
}

const PARAMS := {
	&"torso": {},
	&"cell": {
		"organelles": {"type": "int", "default": 6, "min": 0, "max": 24, "label": "Органеллы", "hint": "Количество видимых органелл (абстрактная клеточная модель)"},
		"membrane_flex": {"type": "float", "default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Гибкость мембраны"},
	},
	&"neck": {},
	&"head": {
		"brain_size": {"type": "float", "default": 0.4, "min": 0.05, "max": 1.0, "step": 0.05, "label": "Размер мозга", "hint": "Больше память и обучение, выше расход энергии"},
	},
	&"tail": {
		"fluke": {"type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Хвостовая лопасть", "hint": "Площадь лопасти для плавания"},
		"prehensile": {"type": "bool", "default": false, "label": "Хватательный"},
	},
	&"limb": {
		"foot": {"type": "enum", "default": "pad", "options": ["pad", "hoof", "claw", "sucker", "web", "hand", "none"], "label": "Окончание", "hint": "Подушечка, копыто, коготь, присоска, перепонка, кисть"},
		"digits": {"type": "int", "default": 4, "min": 0, "max": 8, "label": "Пальцы"},
	},
	&"fin": {
		"fin_area": {"type": "float", "default": 1.0, "min": 0.2, "max": 3.0, "step": 0.1, "label": "Площадь плавника"},
		"fin_type": {"type": "enum", "default": "pectoral", "options": ["pectoral", "dorsal", "pelvic", "caudal", "anal"], "label": "Тип плавника"},
	},
	&"wing": {
		"wing_type": {"type": "enum", "default": "membrane", "options": ["membrane", "feather", "insect"], "label": "Тип крыла", "hint": "Перепончатое, перьевое, насекомоподобное"},
		"chord": {"type": "float", "default": 0.45, "min": 0.1, "max": 1.2, "step": 0.05, "label": "Ширина крыла", "hint": "Ширина относительно длины: влияет на площадь и подъёмную силу"},
	},
	&"tentacle": {
		"suckers": {"type": "bool", "default": true, "label": "Присоски"},
		"prehensile": {"type": "bool", "default": true, "label": "Хватательное"},
	},
	&"antenna": {
		"chemo": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Хеморецепция"},
		"tactile": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Осязание"},
	},
	&"flagellum": {
		"beat": {"type": "float", "default": 0.6, "min": 0.1, "max": 1.0, "step": 0.05, "label": "Частота биения"},
	},
	&"eye": {
		"eye_type": {"type": "enum", "default": "camera", "options": ["camera", "compound", "simple", "pit", "ocellus"], "label": "Тип глаза", "hint": "Камерный, фасеточный, простой, ямковый, глазок"},
		"size": {"type": "float", "default": 0.35, "min": 0.05, "max": 1.0, "step": 0.01, "label": "Размер", "hint": "Относительно толщины части тела"},
		"fov": {"type": "float", "default": 150.0, "min": 20.0, "max": 240.0, "step": 5.0, "label": "Поле зрения глаза, °", "hint": "Угол обзора одного глаза; общее поле зависит от направления глаз"},
		"acuity": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Острота"},
		"night_vision": {"type": "float", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Ночное зрение"},
		"color_vision": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Цветное зрение"},
		"pupil": {"type": "enum", "default": "round", "options": ["round", "slit", "horizontal"], "label": "Зрачок"},
		"iris_color": {"type": "color", "default": "#c8a040", "label": "Цвет радужки"},
	},
	&"ear": {
		"ear_type": {"type": "enum", "default": "external", "options": ["external", "tympanum", "pit"], "label": "Тип уха"},
		"size": {"type": "float", "default": 0.5, "min": 0.05, "max": 2.0, "step": 0.05, "label": "Размер"},
		"sensitivity": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Чувствительность"},
	},
	&"nose": {
		"size": {"type": "float", "default": 0.3, "min": 0.05, "max": 1.0, "step": 0.05, "label": "Размер"},
		"sensitivity": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Чувствительность"},
	},
	&"mouth": {
		"mouth_type": {"type": "enum", "default": "jaws", "options": ["jaws", "beak", "mandibles", "proboscis", "filter", "sucker", "radula", "cell_mouth"], "label": "Ротовой аппарат"},
		"size": {"type": "float", "default": 0.6, "min": 0.1, "max": 1.5, "step": 0.05, "label": "Размер"},
		"bite_force": {"type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Сила укуса"},
		"teeth": {"type": "enum", "default": "mixed", "options": ["none", "grinding", "cutting", "mixed", "fangs"], "label": "Зубы", "hint": "Перетирающие — растения, режущие — мясо"},
		"venom": {"type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Яд"},
	},
	&"horn": {
		"length": {"type": "float", "default": 0.8, "min": 0.1, "max": 4.0, "step": 0.05, "label": "Длина"},
		"base": {"type": "float", "default": 0.25, "min": 0.05, "max": 1.0, "step": 0.05, "label": "Толщина основания"},
		"curvature": {"type": "float", "default": 0.3, "min": -1.0, "max": 1.0, "step": 0.05, "label": "Изгиб"},
		"sharpness": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Острота"},
	},
	&"spike": {
		"length": {"type": "float", "default": 0.5, "min": 0.05, "max": 3.0, "step": 0.05, "label": "Длина"},
		"base": {"type": "float", "default": 0.12, "min": 0.02, "max": 0.6, "step": 0.01, "label": "Толщина"},
		"sharpness": {"type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Острота"},
	},
	&"claw": {
		"length": {"type": "float", "default": 0.6, "min": 0.05, "max": 3.0, "step": 0.05, "label": "Длина"},
		"curvature": {"type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Изгиб"},
		"sharpness": {"type": "float", "default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Острота"},
	},
	&"whisker": {
		"length": {"type": "float", "default": 1.5, "min": 0.2, "max": 5.0, "step": 0.1, "label": "Длина"},
		"count": {"type": "int", "default": 4, "min": 1, "max": 12, "label": "Количество"},
		"sensitivity": {"type": "float", "default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Чувствительность"},
	},
	&"gill": {
		"area": {"type": "float", "default": 1.0, "min": 0.1, "max": 3.0, "step": 0.1, "label": "Площадь", "hint": "Площадь газообмена в воде"},
		"slits": {"type": "int", "default": 4, "min": 1, "max": 8, "label": "Жаберные щели"},
	},
	&"sensor": {
		"sensor_type": {"type": "enum", "default": "electro", "options": ["electro", "thermal", "magnetic", "vibration", "polarized"], "label": "Тип сенсора"},
		"sensitivity": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Чувствительность"},
		"size": {"type": "float", "default": 0.2, "min": 0.05, "max": 0.8, "step": 0.05, "label": "Размер"},
	},
	&"gland": {
		"gland_type": {"type": "enum", "default": "scent", "options": ["venom", "poison_skin", "scent", "ink", "silk", "slime"], "label": "Тип железы"},
		"strength": {"type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Сила"},
	},
	&"light_organ": {
		"color": {"type": "color", "default": "#7cf2ff", "label": "Цвет свечения"},
		"intensity": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Яркость"},
		"size": {"type": "float", "default": 0.2, "min": 0.05, "max": 0.8, "step": 0.05, "label": "Размер"},
	},
	&"shell": {
		"size": {"type": "float", "default": 1.15, "min": 0.6, "max": 2.0, "step": 0.05, "label": "Размер", "hint": "Относительно толщины туловища"},
		"height": {"type": "float", "default": 0.8, "min": 0.3, "max": 2.0, "step": 0.05, "label": "Высота купола"},
		"coverage": {"type": "float", "default": 0.7, "min": 0.2, "max": 1.0, "step": 0.05, "label": "Охват длины"},
		"shell_covering": {"type": "int", "default": 1, "min": 0, "max": 3, "label": "Покров раковины (слот)"},
	},
	&"organ": {
		"organ_type": {"type": "enum", "default": "stomach", "options": [
			"stomach", "gut", "gizzard", "lungs", "trachea", "swim_bladder", "heart", "brain",
			"gonads", "fat_body", "liver", "kidney", "venom_gland", "electric_organ", "photo_tissue", "custom"],
			"label": "Тип органа"},
		"size": {"type": "float", "default": 0.15, "min": 0.01, "max": 0.6, "step": 0.01, "label": "Объём", "hint": "Доля объёма части тела, в которой лежит орган"},
		"efficiency": {"type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05, "label": "Эффективность"},
	},
}

const ENUM_LABELS := {
	"pad": "Подушечка", "hoof": "Копыто", "claw": "Коготь", "sucker": "Присоска", "web": "Перепонка", "hand": "Кисть", "none": "Нет",
	"pectoral": "Грудной", "dorsal": "Спинной", "pelvic": "Брюшной", "caudal": "Хвостовой", "anal": "Анальный",
	"membrane": "Перепонка", "feather": "Перья", "insect": "Насекомое",
	"camera": "Камерный", "compound": "Фасеточный", "simple": "Простой", "pit": "Ямковый", "ocellus": "Глазок",
	"round": "Круглый", "slit": "Щелевидный", "horizontal": "Горизонтальный",
	"external": "Наружное", "tympanum": "Тимпанальное",
	"jaws": "Челюсти", "beak": "Клюв", "mandibles": "Жвалы", "proboscis": "Хоботок", "filter": "Фильтр",
	"radula": "Радула", "cell_mouth": "Клеточный рот",
	"grinding": "Перетирающие", "cutting": "Режущие", "mixed": "Смешанные", "fangs": "Клыки",
	"electro": "Электро", "thermal": "Термо", "magnetic": "Магнито", "vibration": "Вибро", "polarized": "Поляризация",
	"venom": "Ядовитая", "poison_skin": "Кожный яд", "scent": "Пахучая", "ink": "Чернильная", "silk": "Шёлковая", "slime": "Слизистая",
	"stomach": "Желудок", "gut": "Кишечник", "gizzard": "Мускульный желудок", "lungs": "Лёгкие", "trachea": "Трахеи",
	"swim_bladder": "Плавательный пузырь", "heart": "Сердце", "brain": "Мозг", "gonads": "Гонады", "fat_body": "Жировое тело",
	"liver": "Печень", "kidney": "Почки", "venom_gland": "Ядовитая железа", "electric_organ": "Электрический орган",
	"photo_tissue": "Фотосинтезирующая ткань", "custom": "Особый",
}


static func is_spine(kind: StringName) -> bool:
	return SPINE_KINDS.has(kind)


static func is_point(kind: StringName) -> bool:
	return POINT_KINDS.has(kind)


static func label(kind: StringName) -> String:
	return KIND_LABELS.get(kind, String(kind))


static func enum_label(value: String) -> String:
	return ENUM_LABELS.get(value, value)


static func param_specs(kind: StringName) -> Dictionary:
	return PARAMS.get(kind, {})


## Default parameter dictionary for a kind (typed values).
static func default_params(kind: StringName) -> Dictionary:
	var out := {}
	var specs: Dictionary = PARAMS.get(kind, {})
	for key in specs:
		out[key] = _default_value(specs[key])
	return out


static func _default_value(spec: Dictionary):
	match spec.get("type", "float"):
		"int":
			return int(spec.get("default", 0))
		"bool":
			return bool(spec.get("default", false))
		"enum":
			return str(spec.get("default", ""))
		"color":
			return Color.from_string(str(spec.get("default", "#ffffff")), Color.WHITE)
		_:
			return float(spec.get("default", 0.0))


## Clamps / coerces one parameter to its schema. Unknown keys pass through
## untouched (forward compatibility with newer saves).
static func sanitize(kind: StringName, key: String, value):
	var specs: Dictionary = PARAMS.get(kind, {})
	if not specs.has(key):
		return value
	var spec: Dictionary = specs[key]
	match spec.get("type", "float"):
		"int":
			var iv := int(value) if (value is int or value is float) else int(spec.get("default", 0))
			return clampi(iv, int(spec.get("min", -1000000)), int(spec.get("max", 1000000)))
		"bool":
			return bool(value) if (value is bool or value is int or value is float) else bool(spec.get("default", false))
		"enum":
			var sv := str(value)
			var opts: Array = spec.get("options", [])
			return sv if opts.has(sv) else str(spec.get("default", ""))
		"color":
			if value is Color:
				return value
			return Serial.to_color(value, Color.from_string(str(spec.get("default", "#ffffff")), Color.WHITE))
		_:
			var fv := float(value) if (value is int or value is float) else float(spec.get("default", 0.0))
			return clampf(fv, float(spec.get("min", -1.0e9)), float(spec.get("max", 1.0e9)))


## Parameter value -> JSON-safe.
static func param_to_json(value):
	if value is Color:
		return "#" + (value as Color).to_html(true)
	if value is StringName:
		return str(value)
	return value
