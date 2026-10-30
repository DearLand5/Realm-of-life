class_name PartCatalog
extends RefCounted
## Catalogue of parts the player can add: one plain entry per PartSchema kind
## plus ready-made quick presets ("Лапа бегуна", "Плавник", "Клюв"...).
## Entries are data; `build()` produces a standalone subtree (EditorCommands
## format) designed for a parent of radius REFERENCE_RADIUS, and `place()`
## grafts it onto a parent, scaling it to the parent's local thickness.
##
## Entry: {id, label, desc, icon, mode, kind, parents: [kinds], attach: {...},
##         tags: [String], preset: bool}

const REFERENCE_RADIUS := 0.15

## id, label, desc, icon, mode, kind, parents, attach {t, angle, depth, sym, pitch, yaw}, tags
const ENTRIES: Array[Dictionary] = [
	# --- Shape ---
	{"id": "torso_segment", "label": "Брюшко / доп. сегмент тела", "desc": "Ещё одно туловище в конце тела", "icon": "scale", "mode": "shape", "kind": "torso", "parents": ["torso"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["тело", "сегмент"]},
	{"id": "neck", "label": "Шея", "desc": "Гибкая цепь между телом и головой", "icon": "scale", "mode": "shape", "kind": "neck", "parents": ["torso"], "attach": {"t": 1.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["шея"]},
	{"id": "head", "label": "Голова", "desc": "Несёт глаза, рот и мозг", "icon": "eye", "mode": "shape", "kind": "head", "parents": ["neck", "torso"], "attach": {"t": 1.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["голова"]},
	{"id": "tail", "label": "Хвост", "desc": "Баланс, плавание, хватание", "icon": "worm", "mode": "shape", "kind": "tail", "parents": ["torso"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["хвост"]},
	{"id": "tail_fluke", "label": "Хвост-лопасть", "desc": "Хвост с лопастью для плавания", "icon": "fish", "mode": "shape", "kind": "tail", "parents": ["torso"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["хвост", "плавание"], "preset": true},
	{"id": "shell", "label": "Панцирь-раковина", "desc": "Купол, защищающий спину", "icon": "shell", "mode": "shape", "kind": "shell", "parents": ["torso"], "attach": {"t": 0.5, "angle": 90.0, "depth": 1.0, "sym": 0}, "tags": ["броня", "панцирь"]},
	{"id": "cell_body", "label": "Клетка", "desc": "Абстрактная клеточная модель с органеллами", "icon": "cell", "mode": "shape", "kind": "cell", "parents": ["torso", "cell"], "attach": {"t": 0.5, "angle": 90.0, "depth": 0.5, "sym": 0}, "tags": ["клетка"]},
	# --- Limbs ---
	{"id": "leg_run", "label": "Лапа бегуна", "desc": "Длинная трёхсуставная нога с мощными мышцами", "icon": "sprint", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.3, "angle": 300.0, "depth": 0.72, "sym": 1, "pitch": -26.0}, "tags": ["нога", "бег"], "preset": true},
	{"id": "leg_hoof", "label": "Копытная нога", "desc": "Тонкая нога с копытом для стада", "icon": "paw", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.3, "angle": 300.0, "depth": 0.72, "sym": 1, "pitch": -26.0}, "tags": ["нога", "копыто"], "preset": true},
	{"id": "leg_paw", "label": "Лапа с когтями", "desc": "Короткая мягкая лапа с когтем", "icon": "claw", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.3, "angle": 300.0, "depth": 0.72, "sym": 1, "pitch": -26.0}, "tags": ["нога", "коготь"], "preset": true},
	{"id": "arm_hand", "label": "Рука-манипулятор", "desc": "Двухсуставная рука с кистью", "icon": "pointer", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.85, "angle": 320.0, "depth": 0.8, "sym": 1, "pitch": -15.0}, "tags": ["рука", "хватание"], "preset": true},
	{"id": "leg_insect", "label": "Ножки насекомого (3 пары)", "desc": "Метамерные ноги: три пары веером", "icon": "bug", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.75, "angle": 300.0, "depth": 0.85, "sym": 1, "pitch": 0.0}, "tags": ["нога", "насекомое", "метамерия"], "preset": true},
	{"id": "leg_spider", "label": "Паучьи ноги (4 пары)", "desc": "Длинные согнутые ноги, четыре пары", "icon": "spider", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.82, "angle": 320.0, "depth": 0.85, "sym": 1, "pitch": 0.0}, "tags": ["нога", "паук", "метамерия"], "preset": true},
	{"id": "leg_myriapod", "label": "Ножки многоножки (×10)", "desc": "Десять пар коротких ножек вдоль тела", "icon": "worm", "mode": "limbs", "kind": "limb", "parents": ["torso"], "attach": {"t": 0.15, "angle": 285.0, "depth": 0.85, "sym": 1, "pitch": -20.0}, "tags": ["нога", "многоножка", "метамерия"], "preset": true},
	{"id": "fin_pectoral", "label": "Грудной плавник", "desc": "Парный плавник для руления", "icon": "fish", "mode": "limbs", "kind": "fin", "parents": ["torso"], "attach": {"t": 0.82, "angle": 330.0, "depth": 0.9, "sym": 1, "pitch": -10.0}, "tags": ["плавник", "плавание"], "preset": true},
	{"id": "fin_dorsal", "label": "Спинной плавник", "desc": "Стабилизатор на спине", "icon": "fish", "mode": "limbs", "kind": "fin", "parents": ["torso"], "attach": {"t": 0.58, "angle": 90.0, "depth": 0.95, "sym": 0}, "tags": ["плавник", "стабилизатор"], "preset": true},
	{"id": "fin_caudal", "label": "Хвостовой плавник", "desc": "Главный двигатель рыбы", "icon": "fish", "mode": "limbs", "kind": "fin", "parents": ["torso", "tail"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["плавник", "хвост", "плавание"], "preset": true},
	{"id": "flipper", "label": "Ласта", "desc": "Широкая передняя ласта", "icon": "dive", "mode": "limbs", "kind": "fin", "parents": ["torso"], "attach": {"t": 0.8, "angle": 310.0, "depth": 0.85, "sym": 1, "pitch": -20.0}, "tags": ["ласта", "плавание"], "preset": true},
	{"id": "wing_feather", "label": "Перьевое крыло", "desc": "Трёхсуставное крыло с маховыми перьями", "icon": "bird", "mode": "limbs", "kind": "wing", "parents": ["torso"], "attach": {"t": 0.75, "angle": 62.0, "depth": 0.85, "sym": 1, "pitch": -46.0}, "tags": ["крыло", "перья", "полёт"], "preset": true},
	{"id": "wing_membrane", "label": "Перепончатое крыло", "desc": "Кожистая перепонка между длинными пальцами", "icon": "bird", "mode": "limbs", "kind": "wing", "parents": ["torso"], "attach": {"t": 0.75, "angle": 62.0, "depth": 0.85, "sym": 1, "pitch": -46.0}, "tags": ["крыло", "перепонка", "полёт"], "preset": true},
	{"id": "wing_insect", "label": "Крыло насекомого", "desc": "Лёгкое жилковатое крыло", "icon": "bug", "mode": "limbs", "kind": "wing", "parents": ["torso"], "attach": {"t": 0.9, "angle": 72.0, "depth": 0.9, "sym": 1, "pitch": -30.0}, "tags": ["крыло", "насекомое", "полёт"], "preset": true},
	{"id": "tentacle_suckers", "label": "Щупальце с присосками", "desc": "Гибкое хватательное щупальце", "icon": "octopus", "mode": "limbs", "kind": "tentacle", "parents": ["torso"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.55, "sym": 8}, "tags": ["щупальце", "присоски"], "preset": true},
	{"id": "tentacle_thin", "label": "Нить-щупальце", "desc": "Тонкая ловчая нить", "icon": "jellyfish", "mode": "limbs", "kind": "tentacle", "parents": ["torso"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.7, "sym": 6}, "tags": ["щупальце", "медуза"], "preset": true},
	{"id": "antenna", "label": "Усик", "desc": "Хемо- и механорецептор на голове", "icon": "bug", "mode": "limbs", "kind": "antenna", "parents": ["head", "torso"], "attach": {"t": 0.92, "angle": 65.0, "depth": 0.9, "sym": 1}, "tags": ["усик", "антенна", "чувства"], "preset": true},
	{"id": "flagellum", "label": "Жгутик", "desc": "Бьющаяся нить для плавания клетки", "icon": "cell", "mode": "limbs", "kind": "flagellum", "parents": ["cell", "torso"], "attach": {"t": 0.0, "angle": 0.0, "depth": 0.0, "sym": 0}, "tags": ["жгутик", "клетка"], "preset": true},
	# --- Senses ---
	{"id": "eye_camera", "label": "Камерный глаз", "desc": "Острое зрение, хрусталик и круглый зрачок", "icon": "eye", "mode": "senses", "kind": "eye", "parents": ["head", "torso"], "attach": {"t": 0.55, "angle": 30.0, "depth": 0.9, "sym": 1, "yaw": 25.0}, "tags": ["глаз", "зрение"], "preset": true},
	{"id": "eye_predator", "label": "Глаз хищника", "desc": "Узкое поле зрения, щелевой зрачок, ночное зрение", "icon": "eye", "mode": "senses", "kind": "eye", "parents": ["head", "torso"], "attach": {"t": 0.6, "angle": 40.0, "depth": 0.9, "sym": 1, "yaw": 50.0}, "tags": ["глаз", "хищник"], "preset": true},
	{"id": "eye_prey", "label": "Глаз жертвы", "desc": "Почти панорамный обзор по бокам головы", "icon": "eye", "mode": "senses", "kind": "eye", "parents": ["head", "torso"], "attach": {"t": 0.45, "angle": 20.0, "depth": 0.95, "sym": 1, "yaw": 5.0}, "tags": ["глаз", "жертва"], "preset": true},
	{"id": "eye_compound", "label": "Фасеточный глаз", "desc": "Широкий обзор, слабая острота, хорошая реакция", "icon": "bug", "mode": "senses", "kind": "eye", "parents": ["head", "torso"], "attach": {"t": 0.55, "angle": 30.0, "depth": 0.9, "sym": 1, "yaw": 25.0}, "tags": ["глаз", "насекомое"], "preset": true},
	{"id": "eye_simple", "label": "Простой глаз", "desc": "Различает форму на небольшом расстоянии", "icon": "eye", "mode": "senses", "kind": "eye", "parents": ["head", "torso"], "attach": {"t": 0.5, "angle": 45.0, "depth": 0.95, "sym": 1, "yaw": 10.0}, "tags": ["глаз"], "preset": true},
	{"id": "eye_ocellus", "label": "Глазок (оцеллий)", "desc": "Свет и тень", "icon": "eye", "mode": "senses", "kind": "eye", "parents": ["head", "torso"], "attach": {"t": 0.7, "angle": 90.0, "depth": 0.95, "sym": 0}, "tags": ["глаз", "свет"], "preset": true},
	{"id": "ear_external", "label": "Наружное ухо", "desc": "Ушная раковина улавливает звук", "icon": "sound", "mode": "senses", "kind": "ear", "parents": ["head", "torso"], "attach": {"t": 0.22, "angle": 62.0, "depth": 0.95, "sym": 1, "pitch": 10.0, "yaw": -25.0}, "tags": ["ухо", "слух"], "preset": true},
	{"id": "ear_tympanum", "label": "Барабанная перепонка", "desc": "Плоский слуховой орган земноводных и насекомых", "icon": "sound", "mode": "senses", "kind": "ear", "parents": ["head", "torso"], "attach": {"t": 0.2, "angle": 30.0, "depth": 1.0, "sym": 1}, "tags": ["ухо", "слух"], "preset": true},
	{"id": "nose", "label": "Нос", "desc": "Обоняние", "icon": "wind", "mode": "senses", "kind": "nose", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 90.0, "depth": 0.35, "sym": 0}, "tags": ["нос", "запах"]},
	{"id": "whiskers", "label": "Вибриссы", "desc": "Осязающие усы", "icon": "pointer", "mode": "senses", "kind": "whisker", "parents": ["head", "torso"], "attach": {"t": 0.88, "angle": 15.0, "depth": 0.9, "sym": 1, "yaw": -30.0}, "tags": ["усы", "осязание"]},
	{"id": "sensor_electro", "label": "Электрорецептор", "desc": "Чувствует поля живых существ в воде", "icon": "experiment", "mode": "senses", "kind": "sensor", "parents": ["head", "torso"], "attach": {"t": 0.9, "angle": 90.0, "depth": 0.95, "sym": 1}, "tags": ["сенсор", "электро"], "preset": true},
	{"id": "sensor_thermal", "label": "Тепловая ямка", "desc": "Видит тепло тёплых тел", "icon": "thermometer", "mode": "senses", "kind": "sensor", "parents": ["head", "torso"], "attach": {"t": 0.8, "angle": 45.0, "depth": 0.95, "sym": 1}, "tags": ["сенсор", "тепло"], "preset": true},
	{"id": "sensor_magnetic", "label": "Магниторецептор", "desc": "Чувство направления", "icon": "magnet", "mode": "senses", "kind": "sensor", "parents": ["head", "torso"], "attach": {"t": 0.5, "angle": 90.0, "depth": 0.8, "sym": 0}, "tags": ["сенсор", "магнит"], "preset": true},
	{"id": "sensor_vibration", "label": "Боковая линия", "desc": "Чувствует колебания среды", "icon": "sound", "mode": "senses", "kind": "sensor", "parents": ["torso"], "attach": {"t": 0.6, "angle": 5.0, "depth": 0.98, "sym": 1}, "tags": ["сенсор", "вибрация"], "preset": true},
	# --- Organs ---
	{"id": "mouth_jaws", "label": "Челюсти", "desc": "Универсальный ротовой аппарат с зубами", "icon": "skull", "mode": "organs", "kind": "mouth", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.4, "sym": 0}, "tags": ["рот", "зубы"]},
	{"id": "mouth_beak", "label": "Клюв", "desc": "Роговой клюв птицы", "icon": "bird", "mode": "organs", "kind": "mouth", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.15, "sym": 0}, "tags": ["рот", "клюв"], "preset": true},
	{"id": "mouth_mandibles", "label": "Жвалы", "desc": "Боковые челюсти насекомых", "icon": "bug", "mode": "organs", "kind": "mouth", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.3, "sym": 0}, "tags": ["рот", "жвалы"], "preset": true},
	{"id": "mouth_proboscis", "label": "Хоботок", "desc": "Сосущий ротовой аппарат", "icon": "drop", "mode": "organs", "kind": "mouth", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.2, "sym": 0}, "tags": ["рот", "нектар"], "preset": true},
	{"id": "mouth_filter", "label": "Фильтрующий рот", "desc": "Процеживает планктон", "icon": "filter", "mode": "organs", "kind": "mouth", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.4, "sym": 0}, "tags": ["рот", "фильтрация"], "preset": true},
	{"id": "fangs", "label": "Ядовитые клыки", "desc": "Челюсти с клыками и ядом", "icon": "skull", "mode": "organs", "kind": "mouth", "parents": ["head", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.4, "sym": 0}, "tags": ["рот", "яд", "клыки"], "preset": true},
	{"id": "horns", "label": "Рога", "desc": "Парные изогнутые рога", "icon": "mountain", "mode": "organs", "kind": "horn", "parents": ["head", "torso"], "attach": {"t": 0.18, "angle": 78.0, "depth": 0.95, "sym": 1, "pitch": 8.0, "yaw": -38.0}, "tags": ["рога", "оружие"], "preset": true},
	{"id": "horn_single", "label": "Одиночный рог", "desc": "Прямой рог на лбу", "icon": "mountain", "mode": "organs", "kind": "horn", "parents": ["head", "torso"], "attach": {"t": 0.8, "angle": 90.0, "depth": 0.95, "sym": 0}, "tags": ["рога", "единорог"], "preset": true},
	{"id": "antlers", "label": "Ветвистые рога", "desc": "Длинные рога с отростками", "icon": "tree", "mode": "organs", "kind": "horn", "parents": ["head", "torso"], "attach": {"t": 0.25, "angle": 80.0, "depth": 0.95, "sym": 1, "pitch": 10.0, "yaw": -20.0}, "tags": ["рога", "олень"], "preset": true},
	{"id": "spike", "label": "Шип", "desc": "Защитный шип", "icon": "warning", "mode": "organs", "kind": "spike", "parents": ["torso", "tail", "head"], "attach": {"t": 0.5, "angle": 90.0, "depth": 1.0, "sym": 0}, "tags": ["шип", "защита"]},
	{"id": "spike_row", "label": "Гребень шипов (×6)", "desc": "Ряд шипов вдоль спины", "icon": "warning", "mode": "organs", "kind": "spike", "parents": ["torso", "tail"], "attach": {"t": 0.15, "angle": 90.0, "depth": 1.0, "sym": 0}, "tags": ["шип", "гребень", "метамерия"], "preset": true},
	{"id": "claw", "label": "Коготь", "desc": "Острый коготь на конце конечности", "icon": "claw", "mode": "organs", "kind": "claw", "parents": ["limb", "torso"], "attach": {"t": 1.0, "angle": 270.0, "depth": 0.6, "sym": 0}, "tags": ["коготь", "оружие"]},
	{"id": "gills", "label": "Жабры", "desc": "Газообмен в воде", "icon": "drop", "mode": "organs", "kind": "gill", "parents": ["head", "torso"], "attach": {"t": 0.1, "angle": 10.0, "depth": 0.97, "sym": 1}, "tags": ["жабры", "дыхание"]},
	{"id": "gland_venom", "label": "Ядовитая железа", "desc": "Вырабатывает яд", "icon": "skull", "mode": "organs", "kind": "gland", "parents": ["head", "torso"], "attach": {"t": 0.5, "angle": 90.0, "depth": 0.5, "sym": 0}, "tags": ["железа", "яд"], "preset": true},
	{"id": "gland_silk", "label": "Шёлковая железа", "desc": "Паутина и коконы", "icon": "spider", "mode": "organs", "kind": "gland", "parents": ["torso"], "attach": {"t": 0.02, "angle": 270.0, "depth": 0.8, "sym": 0}, "tags": ["железа", "шёлк"], "preset": true},
	{"id": "gland_ink", "label": "Чернильная железа", "desc": "Чернильное облако для бегства", "icon": "octopus", "mode": "organs", "kind": "gland", "parents": ["torso"], "attach": {"t": 0.35, "angle": 90.0, "depth": 0.5, "sym": 0}, "tags": ["железа", "чернила"], "preset": true},
	{"id": "light_organ", "label": "Светящийся орган", "desc": "Биолюминесценция", "icon": "sun", "mode": "organs", "kind": "light_organ", "parents": ["torso", "head"], "attach": {"t": 0.5, "angle": 270.0, "depth": 1.0, "sym": 1}, "tags": ["свет", "биолюминесценция"]},
	{"id": "lure", "label": "Светящаяся приманка", "desc": "Усик со светящимся кончиком", "icon": "star", "mode": "organs", "kind": "light_organ", "parents": ["head", "torso"], "attach": {"t": 0.8, "angle": 90.0, "depth": 1.0, "sym": 0}, "tags": ["свет", "приманка"], "preset": true},
]

static var _index := {}


static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in ENTRIES:
		out.append(e)
	for t in PartSchema.PARAMS[&"organ"]["organ_type"]["options"]:
		out.append(organ_entry(str(t)))
	return out


static func organ_entry(organ_type: String) -> Dictionary:
	return {"id": "organ_" + organ_type, "label": PartSchema.enum_label(organ_type), "desc": "Внутренний орган (виден в рентгене)",
		"icon": "heart", "mode": "anatomy", "kind": "organ", "parents": ["torso", "head"],
		"attach": {"t": 0.5, "angle": 90.0 if organ_type in ["lungs", "swim_bladder", "brain", "photo_tissue", "trachea"] else 270.0, "depth": 0.3, "sym": 0},
		"tags": ["орган", organ_type]}


static func get_entry(id: String) -> Dictionary:
	if _index.is_empty():
		for e in entries():
			_index[e["id"]] = e
	return _index.get(id, {})


## Entries of an editor mode (organ entries belong to "anatomy").
static func for_mode(mode: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries():
		if StringName(e["mode"]) == mode:
			out.append(e)
	return out


# --- Building -------------------------------------------------------------------

## Standalone subtree dict of an entry (top part designed for REFERENCE_RADIUS).
static func build(id: String) -> Dictionary:
	var e := get_entry(id)
	if e.is_empty():
		return {}
	var plan := BodyPlan.new()
	var top := _make_top(id, StringName(e["kind"]), plan)
	return EditorCommands.subtree_from_plan(plan) if top >= 0 else {}


static func _chain(kind: StringName, r0: float, segs: Array, fn: StringName = &"none", muscle: float = -1.0, fast: float = 0.5) -> BodyPart:
	var p := BodyPlanPresets.chain(kind, r0, segs, fn)
	if muscle >= 0.0:
		p.muscle_ratio = muscle
		p.fast_twitch = fast
	return p


## Builds the top part (and its children) into `plan`, returns the top id.
static func _make_top(id: String, kind: StringName, plan: BodyPlan) -> int:
	var part: BodyPart
	var kids: Array = []   # [part, t, angle, depth, sym, pitch, yaw]
	match id:
		"torso_segment":
			part = _chain(&"torso", 0.13, [[0.14, 0.16, 0, 0, 1.0], [0.12, 0.1, 0, 0, 1.0]])
		"neck":
			part = _chain(&"neck", 0.1, [[0.12, 0.085, 20], [0.1, 0.08, 6]])
		"head":
			part = _chain(&"head", 0.09, [[0.12, 0.1, -20], [0.1, 0.06, -6]])
			part.set_param("brain_size", 0.45)
		"tail":
			part = _chain(&"tail", 0.06, [[0.14, 0.05, -10], [0.14, 0.035, 4], [0.12, 0.02, 4]])
		"tail_fluke":
			part = _chain(&"tail", 0.07, [[0.16, 0.06, 0], [0.16, 0.04, 6], [0.12, 0.02, 4]], &"swim", 0.5, 0.5)
			part.set_param("fluke", 0.9)
		"shell":
			part = BodyPart.new(&"shell")
		"cell_body":
			part = _chain(&"cell", 0.08, [[0.1, 0.1]])
		"leg_run":
			part = _chain(&"limb", 0.07, [[0.26, 0.06, 0, 26], [0.28, 0.04, 0, -48], [0.18, 0.025, 0, 28], [0.07, 0.02, 0, 64]], &"run", 0.6, 0.85)
			part.set_param("foot", "claw")
			part.label = "Нога бегуна"
		"leg_hoof":
			part = _chain(&"limb", 0.075, [[0.3, 0.055, 0, -6], [0.3, 0.04, 0, 6], [0.14, 0.03, 0, 18]], &"run", 0.5, 0.6)
			part.set_param("foot", "hoof")
			part.label = "Нога"
		"leg_paw":
			part = _chain(&"limb", 0.07, [[0.24, 0.055, 0, -4], [0.24, 0.04, 0, 4], [0.09, 0.032, 0, 50]], &"run", 0.55, 0.8)
			part.set_param("foot", "claw")
			part.label = "Лапа"
			kids.append([BodyPlanPresets.point(&"claw", {"length": 0.9, "curvature": 0.7, "sharpness": 0.9}), 1.0, 270.0, 0.6, 0, 0.0, 0.0])
		"arm_hand":
			part = _chain(&"limb", 0.03, [[0.12, 0.025, 0, 35], [0.1, 0.018, 0, 40]], &"grasp", 0.4, 0.4)
			part.set_param("foot", "hand")
			part.label = "Рука"
		"leg_insect":
			part = _chain(&"limb", 0.025, [[0.1, 0.022, 40, 0], [0.13, 0.015, -80, 0], [0.07, 0.01, -10, 0]], &"walk", 0.4, 0.8)
			part.set_param("foot", "claw")
			part.repeat_count = 3
			part.repeat_span = 0.22
			part.repeat_yaw = 80.0
			part.label = "Ножка"
		"leg_spider":
			part = _chain(&"limb", 0.03, [[0.18, 0.025, 50, 0], [0.22, 0.018, -70, 0], [0.18, 0.012, -30, 0]], &"walk", 0.4, 0.8)
			part.set_param("foot", "claw")
			part.repeat_count = 4
			part.repeat_span = 0.16
			part.repeat_yaw = 110.0
			part.label = "Нога паука"
		"leg_myriapod":
			part = _chain(&"limb", 0.02, [[0.07, 0.016, 0, 0], [0.07, 0.01, 0, 0]], &"walk", 0.3, 0.3)
			part.set_param("foot", "claw")
			part.repeat_count = 10
			part.repeat_span = 0.7
			part.label = "Ножка"
		"fin_pectoral":
			part = _chain(&"fin", 0.03, [[0.18, 0.015, 0, -55]], &"swim")
			part.set_param("fin_type", "pectoral")
			part.set_param("fin_area", 1.2)
		"fin_dorsal":
			part = _chain(&"fin", 0.03, [[0.2, 0.012, 0, -45]], &"swim")
			part.set_param("fin_type", "dorsal")
			part.set_param("fin_area", 1.4)
		"fin_caudal":
			part = _chain(&"fin", 0.04, [[0.3, 0.015, 0]], &"swim")
			part.set_param("fin_type", "caudal")
			part.set_param("fin_area", 2.2)
		"flipper":
			part = _chain(&"fin", 0.05, [[0.2, 0.03, 0, -40], [0.16, 0.012, 0, -20]], &"swim", 0.5, 0.4)
			part.set_param("fin_type", "pectoral")
			part.set_param("fin_area", 2.0)
			part.label = "Ласта"
		"wing_feather":
			part = _chain(&"wing", 0.04, [[0.2, 0.035, 0, -8], [0.26, 0.025, 0, 16], [0.22, 0.012, 0, -22]], &"fly", 0.7, 0.6)
			part.set_param("wing_type", "feather")
			part.set_param("chord", 0.62)
			part.label = "Крыло"
		"wing_membrane":
			part = _chain(&"wing", 0.04, [[0.2, 0.03, 0, -10], [0.3, 0.02, 0, 15], [0.26, 0.01, 0, -20]], &"fly", 0.7, 0.6)
			part.set_param("wing_type", "membrane")
			part.set_param("chord", 0.5)
			part.label = "Крыло"
		"wing_insect":
			part = _chain(&"wing", 0.012, [[0.3, 0.008, 0, -62]], &"fly", 0.7, 0.9)
			part.set_param("wing_type", "insect")
			part.set_param("chord", 0.9)
			part.label = "Крыло"
		"tentacle_suckers":
			part = _chain(&"tentacle", 0.05, [[0.2, 0.04, 0, -12], [0.2, 0.028, 0, -18], [0.18, 0.018, 0, -14], [0.16, 0.008, 0, -10]], &"grasp", 0.7, 0.5)
		"tentacle_thin":
			part = _chain(&"tentacle", 0.02, [[0.25, 0.015, 0, -6], [0.25, 0.01, 0, -8], [0.25, 0.005, 0, -6]], &"grasp", 0.3, 0.3)
			part.set_param("suckers", false)
			part.set_param("prehensile", false)
		"antenna":
			part = _chain(&"antenna", 0.012, [[0.2, 0.01, 25, 35], [0.2, 0.006, 10, 5]])
		"flagellum":
			part = _chain(&"flagellum", 0.015, [[0.2, 0.01, 0, 20], [0.2, 0.008, 0, -30], [0.2, 0.005, 0, 30]], &"swim")
		"eye_camera":
			part = BodyPlanPresets.point(&"eye", {"eye_type": "camera", "size": 0.35, "fov": 150.0, "acuity": 0.7})
		"eye_predator":
			part = BodyPlanPresets.point(&"eye", {"eye_type": "camera", "size": 0.3, "fov": 130.0, "acuity": 0.9, "night_vision": 0.8, "pupil": "slit", "iris_color": Color(0.85, 0.7, 0.15)})
		"eye_prey":
			part = BodyPlanPresets.point(&"eye", {"eye_type": "camera", "size": 0.34, "fov": 200.0, "acuity": 0.55, "night_vision": 0.4, "pupil": "horizontal", "iris_color": Color(0.3, 0.2, 0.1)})
		"eye_compound":
			part = BodyPlanPresets.point(&"eye", {"eye_type": "compound", "size": 0.6, "fov": 200.0, "acuity": 0.4, "color_vision": 0.8})
		"eye_simple":
			part = BodyPlanPresets.point(&"eye", {"eye_type": "simple", "size": 0.25, "fov": 120.0, "acuity": 0.3, "color_vision": 0.2})
		"eye_ocellus":
			part = BodyPlanPresets.point(&"eye", {"eye_type": "ocellus", "size": 0.2, "fov": 160.0, "acuity": 0.1, "color_vision": 0.0})
		"ear_external":
			part = BodyPlanPresets.point(&"ear", {"ear_type": "external", "size": 0.6, "sensitivity": 0.7})
		"ear_tympanum":
			part = BodyPlanPresets.point(&"ear", {"ear_type": "tympanum", "size": 0.4, "sensitivity": 0.6})
		"nose":
			part = BodyPlanPresets.point(&"nose", {})
		"whiskers":
			part = BodyPlanPresets.point(&"whisker", {"length": 1.6, "count": 5})
		"sensor_electro":
			part = BodyPlanPresets.point(&"sensor", {"sensor_type": "electro"})
		"sensor_thermal":
			part = BodyPlanPresets.point(&"sensor", {"sensor_type": "thermal"})
		"sensor_magnetic":
			part = BodyPlanPresets.point(&"sensor", {"sensor_type": "magnetic"})
		"sensor_vibration":
			part = BodyPlanPresets.point(&"sensor", {"sensor_type": "vibration", "sensitivity": 0.7, "size": 0.1})
		"mouth_jaws":
			part = BodyPlanPresets.point(&"mouth", {})
		"mouth_beak":
			part = BodyPlanPresets.point(&"mouth", {"mouth_type": "beak", "size": 1.3, "teeth": "none", "bite_force": 0.4})
		"mouth_mandibles":
			part = BodyPlanPresets.point(&"mouth", {"mouth_type": "mandibles", "teeth": "grinding", "size": 0.8})
		"mouth_proboscis":
			part = BodyPlanPresets.point(&"mouth", {"mouth_type": "proboscis", "teeth": "none", "size": 0.7, "bite_force": 0.1})
		"mouth_filter":
			part = BodyPlanPresets.point(&"mouth", {"mouth_type": "filter", "teeth": "none", "size": 1.0, "bite_force": 0.1})
		"fangs":
			part = BodyPlanPresets.point(&"mouth", {"mouth_type": "jaws", "teeth": "fangs", "venom": 0.8, "bite_force": 0.7, "size": 0.7})
		"horns":
			part = BodyPlanPresets.point(&"horn", {"length": 1.6, "base": 0.3, "curvature": 0.45, "sharpness": 0.6})
		"horn_single":
			part = BodyPlanPresets.point(&"horn", {"length": 2.0, "base": 0.25, "curvature": 0.0, "sharpness": 0.9})
		"antlers":
			part = BodyPlanPresets.point(&"horn", {"length": 2.8, "base": 0.2, "curvature": 0.6, "sharpness": 0.5})
			kids.append([BodyPlanPresets.point(&"horn", {"length": 1.2, "base": 0.12, "curvature": 0.4, "sharpness": 0.6}), 0.5, 90.0, 0.9, 0, 30.0, 0.0])
			kids.append([BodyPlanPresets.point(&"horn", {"length": 0.9, "base": 0.1, "curvature": 0.4, "sharpness": 0.6}), 0.8, 90.0, 0.9, 0, 30.0, 0.0])
		"spike":
			part = BodyPlanPresets.point(&"spike", {})
		"spike_row":
			part = BodyPlanPresets.point(&"spike", {"length": 0.7, "base": 0.1, "sharpness": 0.9})
			part.repeat_count = 6
			part.repeat_span = 0.7
		"claw":
			part = BodyPlanPresets.point(&"claw", {})
		"gills":
			part = BodyPlanPresets.point(&"gill", {})
		"gland_venom":
			part = BodyPlanPresets.point(&"gland", {"gland_type": "venom", "strength": 0.7})
		"gland_silk":
			part = BodyPlanPresets.point(&"gland", {"gland_type": "silk", "strength": 0.7})
		"gland_ink":
			part = BodyPlanPresets.point(&"gland", {"gland_type": "ink", "strength": 0.8})
		"light_organ":
			part = BodyPlanPresets.point(&"light_organ", {})
		"lure":
			part = BodyPlanPresets.point(&"light_organ", {"intensity": 0.9, "size": 0.35, "color": Color("#ffd84a")})
		_:
			if id.begins_with("organ_"):
				var ot := id.trim_prefix("organ_")
				part = BodyPlanPresets.point(&"organ", {"organ_type": ot, "size": _organ_size(ot)})
			else:
				part = BodyPart.new(kind)
				if part.is_spine():
					part.base_radius = 0.05
					part.segments.append(BodySegment.new(0.2, 0.04))
	var top := plan.add_part(part, -1)
	for k in kids:
		BodyPlanPresets.att(plan, k[0], top, k[1], k[2], k[3], k[4], k[5], k[6])
	return top


static func _organ_size(t: String) -> float:
	match t:
		"lungs", "gut", "stomach": return 0.12
		"swim_bladder": return 0.08
		"brain": return 0.15
		"heart", "kidney", "gonads", "liver": return 0.04
		"fat_body": return 0.1
	return 0.06


# --- Placement ---------------------------------------------------------------------------

## The parent an entry should attach to: the selection if acceptable, else the
## first part of a preferred kind, else the root.
static func suggest_parent(plan: BodyPlan, entry: Dictionary, selected_id: int) -> int:
	var accepted: Array = entry.get("parents", [])
	var sel := plan.get_part(selected_id)
	if sel != null and (accepted.is_empty() or accepted.has(str(sel.kind))):
		return sel.id
	for k in accepted:
		var l := plan.parts_of_kind(StringName(k))
		if not l.is_empty():
			return l[0].id
	return plan.root_id


## Grafts catalogue entry `id` under `parent_id` (-1 = suggested parent).
## `symmetric` = apply the editor's symmetry toggle to paired entries.
## Returns the new top part id (-1 on failure).
static func place(plan: BodyPlan, id: String, parent_id: int, symmetric: bool = true, overrides: Dictionary = {}) -> int:
	var e := get_entry(id)
	var sub := build(id)
	if e.is_empty() or sub.is_empty():
		return -1
	var parent := plan.get_part(parent_id)
	if parent == null:
		parent = plan.root()
	var at: Dictionary = e.get("attach", {})
	var attach := {
		"attach_t": float(at.get("t", 0.5)), "attach_angle": float(at.get("angle", 90.0)),
		"attach_depth": float(at.get("depth", 1.0)), "pitch": float(at.get("pitch", 0.0)), "yaw": float(at.get("yaw", 0.0)),
	}
	var sym := int(at.get("sym", 0))
	if sym == 1 and not symmetric:
		sym = 0
	attach["symmetry"] = sym
	for k in overrides:
		attach[k] = overrides[k]
	_avoid_overlap(plan, parent, StringName(e["kind"]), attach)
	var top_id := EditorCommands.graft(plan, sub, parent.id, attach)
	var top := plan.get_part(top_id)
	if top != null:
		_fit_to_parent(plan, top, parent, float(attach["attach_t"]))
	return top_id


## Scales a spine part's chain to the parent's local radius (point parts are
## relative to the parent already).
static func _fit_to_parent(plan: BodyPlan, top: BodyPart, parent: BodyPart, t: float) -> void:
	var k := parent_fit_scale(parent, t)
	scale_subtree(plan, top, k)


static func parent_fit_scale(parent: BodyPart, t: float) -> float:
	var r := EditorCommands.radius_at(parent, t) * parent.scale
	if parent.kind in [&"head", &"neck", &"tail"]:
		r *= 1.3
	return clampf(r / REFERENCE_RADIUS, 0.04, 20.0)


## Multiplies lengths/radii of the spine parts in a subtree (point parts scale with their parent).
static func scale_subtree(plan: BodyPlan, top: BodyPart, k: float) -> void:
	var list: Array[BodyPart] = [top]
	list.append_array(plan.descendants_of(top.id))
	for p in list:
		if p.is_spine():
			p.base_radius = clampf(p.base_radius * k, 0.001, 10.0)
			for s in p.segments:
				s.length = clampf(s.length * k, 0.005, 20.0)
				s.radius = clampf(s.radius * k, 0.001, 10.0)


## Moves the default attach_t when an identical part already sits there.
static func _avoid_overlap(plan: BodyPlan, parent: BodyPart, kind: StringName, attach: Dictionary) -> void:
	var t: float = attach["attach_t"]
	if t <= 0.001 or t >= 0.999:
		return
	var tries := [0.0, 0.15, -0.15, 0.3, -0.3, 0.45]
	for off in tries:
		var cand: float = clampf(t + off, 0.03, 0.97)
		var clash := false
		for c in plan.children_of(parent.id):
			if c.kind == kind and absf(c.attach_t - cand) < 0.06 and absf(wrapf(c.attach_angle - float(attach["attach_angle"]), -180.0, 180.0)) < 25.0:
				clash = true
				break
		if not clash:
			attach["attach_t"] = cand
			return
