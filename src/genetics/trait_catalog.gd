class_name TraitCatalog
extends RefCounted
## Catalogue of quantitative heritable traits (simplified Mendelian model).
##
## Every trait is controlled by `loci` diploid loci. An allele is a normalized
## value 0..1. Locus expression with dominance h:
##     v = h * max(a, b) + (1 - h) * min(a, b)
##   h = 0.5 → additive (co-dominant), h = 1 → "high" allele dominant,
##   h = 0   → "high" allele recessive (expressed only when homozygous).
## Polygenic traits average their loci. The real value is
##     lerp(min, max, mean_v).
## Loci are laid out on chromosomes in catalogue order; recombination uses
## crossovers between consecutive loci of a chromosome (linkage).
##
## `scope` documents what the trait influences — shown in the genetics editor.

const CHROMOSOMES := 6

## id, category, chromosome, label, min, max, default, loci, h, sigma (relative mutation step), scope
const DEFS := [
	# --- Morphology (chr 0) ---------------------------------------------------------
	{"id": &"size", "cat": &"anatomy", "chr": 0, "label": "Размер тела", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 3, "h": 0.5, "sigma": 0.05, "scope": "Масштаб всего тела: масса ∝ размер³, площадь ∝ размер²"},
	{"id": &"limb_length", "cat": &"anatomy", "chr": 0, "label": "Длина конечностей", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Длина шага, скорость, высота стойки"},
	{"id": &"limb_thickness", "cat": &"anatomy", "chr": 0, "label": "Толщина конечностей", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Прочность опоры и сила мышц, масса"},
	{"id": &"torso_length", "cat": &"anatomy", "chr": 0, "label": "Длина туловища", "min": 0.7, "max": 1.4, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.04, "scope": "Длина тела, объём внутренних органов"},
	{"id": &"torso_girth", "cat": &"anatomy", "chr": 0, "label": "Обхват туловища", "min": 0.7, "max": 1.4, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.04, "scope": "Объём, масса, теплоёмкость, обтекаемость"},
	{"id": &"head_size", "cat": &"anatomy", "chr": 0, "label": "Размер головы", "min": 0.7, "max": 1.4, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Размер рта, мозга и органов чувств на голове"},
	{"id": &"tail_length", "cat": &"anatomy", "chr": 0, "label": "Длина хвоста", "min": 0.5, "max": 1.8, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.06, "scope": "Баланс, плавание, хватание"},
	{"id": &"appendage_size", "cat": &"anatomy", "chr": 0, "label": "Рога, шипы, когти", "min": 0.5, "max": 1.8, "default": 1.0, "loci": 2, "h": 0.6, "sigma": 0.06, "scope": "Урон в бою, защита, масса"},
	{"id": &"wing_area", "cat": &"anatomy", "chr": 1, "label": "Площадь крыльев и плавников", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Подъёмная сила, тяга в воде"},
	{"id": &"muscle_mass", "cat": &"anatomy", "chr": 1, "label": "Мускулатура", "min": 0.6, "max": 1.5, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.04, "scope": "Сила и скорость, но выше расход энергии"},
	{"id": &"fat_reserve", "cat": &"anatomy", "chr": 1, "label": "Жировой запас", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.06, "scope": "Запас энергии и теплоизоляция, но лишняя масса"},
	{"id": &"armor", "cat": &"anatomy", "chr": 1, "label": "Толщина брони", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Защита от урона, масса, гибкость"},
	{"id": &"fur_length", "cat": &"anatomy", "chr": 1, "label": "Густота покрова", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.06, "scope": "Теплоизоляция шерсти/перьев"},
	# --- Coloration (chr 1) -----------------------------------------------------------
	{"id": &"hue_shift", "cat": &"color", "chr": 1, "label": "Сдвиг оттенка", "min": -0.15, "max": 0.15, "default": 0.0, "loci": 2, "h": 0.5, "sigma": 0.06, "scope": "Оттенок всех покровов"},
	{"id": &"saturation", "cat": &"color", "chr": 1, "label": "Насыщенность", "min": 0.5, "max": 1.5, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Яркость окраски (сигнал/маскировка)"},
	{"id": &"brightness", "cat": &"color", "chr": 1, "label": "Светлота", "min": 0.6, "max": 1.4, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Светлота окраски, нагрев на солнце"},
	{"id": &"pattern_scale", "cat": &"color", "chr": 1, "label": "Масштаб узора", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Размер пятен и полос"},
	{"id": &"pattern_contrast", "cat": &"color", "chr": 1, "label": "Контраст узора", "min": 0.0, "max": 1.0, "default": 0.6, "loci": 1, "h": 0.5, "sigma": 0.06, "scope": "Выраженность узора"},
	{"id": &"melanism", "cat": &"color", "chr": 1, "label": "Меланизм", "min": 0.0, "max": 1.0, "default": 0.0, "loci": 1, "h": 0.9, "sigma": 0.04, "scope": "Доминантное затемнение окраски"},
	{"id": &"albinism", "cat": &"color", "chr": 1, "label": "Альбинизм", "min": 0.0, "max": 1.0, "default": 0.0, "loci": 1, "h": 0.0, "sigma": 0.04, "scope": "Рецессивное отсутствие пигмента (только у гомозигот)"},
	# --- Physiology (chr 2) -----------------------------------------------------------
	{"id": &"metabolism", "cat": &"physiology", "chr": 2, "label": "Скорость обмена", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.04, "scope": "Быстрее рост и восстановление, больше еды"},
	{"id": &"endothermy", "cat": &"physiology", "chr": 2, "label": "Теплокровность", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 2, "h": 0.5, "sigma": 0.03, "scope": "Независимость от температуры ценой расхода энергии"},
	{"id": &"thermal_optimum", "cat": &"physiology", "chr": 2, "label": "Оптимум температуры, °C", "min": -10.0, "max": 40.0, "default": 20.0, "loci": 2, "h": 0.5, "sigma": 0.03, "scope": "Предпочитаемая температура среды"},
	{"id": &"thermal_tolerance", "cat": &"physiology", "chr": 2, "label": "Терпимость к температуре", "min": 4.0, "max": 25.0, "default": 10.0, "loci": 2, "h": 0.5, "sigma": 0.04, "scope": "Ширина комфортного диапазона"},
	{"id": &"digestion_plant", "cat": &"physiology", "chr": 2, "label": "Усвоение растений", "min": 0.0, "max": 1.0, "default": 0.6, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "КПД переваривания растительной пищи"},
	{"id": &"digestion_meat", "cat": &"physiology", "chr": 2, "label": "Усвоение мяса", "min": 0.0, "max": 1.0, "default": 0.3, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "КПД переваривания животной пищи"},
	{"id": &"digestion_carrion", "cat": &"physiology", "chr": 2, "label": "Усвоение падали", "min": 0.0, "max": 1.0, "default": 0.1, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Устойчивость к токсинам разложения"},
	{"id": &"water_retention", "cat": &"physiology", "chr": 2, "label": "Удержание воды", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Выживание в засуху"},
	{"id": &"immune", "cat": &"physiology", "chr": 2, "label": "Иммунитет", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 2, "h": 0.6, "sigma": 0.05, "scope": "Сопротивление болезням, но энергозатратно"},
	{"id": &"regeneration", "cat": &"physiology", "chr": 2, "label": "Регенерация", "min": 0.0, "max": 1.0, "default": 0.3, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Скорость заживления ран"},
	{"id": &"photosynthesis", "cat": &"physiology", "chr": 2, "label": "Фотосинтез", "min": 0.0, "max": 1.0, "default": 0.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Энергия от света (нужна фотосинтезирующая ткань)"},
	{"id": &"oxygen_efficiency", "cat": &"physiology", "chr": 2, "label": "Эффективность дыхания", "min": 0.5, "max": 1.5, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Выносливость, жизнь в разреженном воздухе/тёплой воде"},
	# --- Life history (chr 3) ---------------------------------------------------------
	{"id": &"lifespan", "cat": &"life", "chr": 3, "label": "Продолжительность жизни", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Множитель к видовой продолжительности жизни"},
	{"id": &"maturity_age", "cat": &"life", "chr": 3, "label": "Возраст созревания", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Раннее созревание = быстрее поколения"},
	{"id": &"growth_rate", "cat": &"life", "chr": 3, "label": "Скорость роста", "min": 0.5, "max": 1.5, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Скорость развития молодых"},
	{"id": &"clutch_size", "cat": &"life", "chr": 3, "label": "Размер помёта/кладки", "min": 1.0, "max": 12.0, "default": 3.0, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Число потомков за раз (r/K-стратегия)"},
	{"id": &"offspring_investment", "cat": &"life", "chr": 3, "label": "Вклад в потомка", "min": 0.02, "max": 0.4, "default": 0.12, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Доля массы родителя на одного потомка"},
	{"id": &"fertility", "cat": &"life", "chr": 3, "label": "Плодовитость", "min": 0.2, "max": 1.0, "default": 0.7, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Вероятность успешного зачатия"},
	{"id": &"gestation", "cat": &"life", "chr": 3, "label": "Длительность вынашивания", "min": 0.5, "max": 2.0, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Дольше — крупнее и развитее потомство"},
	{"id": &"breeding_season", "cat": &"life", "chr": 3, "label": "Сезонность размножения", "min": 0.0, "max": 1.0, "default": 0.3, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "0 — круглый год, 1 — только весной"},
	{"id": &"mutation_rate", "cat": &"life", "chr": 3, "label": "Частота мутаций", "min": 0.2, "max": 3.0, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Эволюционирующая изменчивость"},
	# --- Behaviour (chr 4) ------------------------------------------------------------
	{"id": &"aggression", "cat": &"behavior", "chr": 4, "label": "Агрессивность", "min": 0.0, "max": 1.0, "default": 0.3, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Склонность к нападению и конфликтам"},
	{"id": &"boldness", "cat": &"behavior", "chr": 4, "label": "Смелость", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Дистанция бегства, риск"},
	{"id": &"sociality", "cat": &"behavior", "chr": 4, "label": "Социальность", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "Стайность, стадность, кооперация"},
	{"id": &"curiosity", "cat": &"behavior", "chr": 4, "label": "Любопытство", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Исследование территории"},
	{"id": &"territoriality", "cat": &"behavior", "chr": 4, "label": "Территориальность", "min": 0.0, "max": 1.0, "default": 0.3, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Охрана участка"},
	{"id": &"parental_care", "cat": &"behavior", "chr": 4, "label": "Забота о потомстве", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Выживаемость детёнышей ценой времени родителей"},
	{"id": &"activity_phase", "cat": &"behavior", "chr": 4, "label": "Суточная активность", "min": 0.0, "max": 1.0, "default": 0.0, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "0 — дневной, 0.5 — сумеречный, 1 — ночной"},
	{"id": &"vigilance", "cat": &"behavior", "chr": 4, "label": "Бдительность", "min": 0.0, "max": 1.0, "default": 0.5, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Раннее обнаружение угроз, меньше времени на еду"},
	{"id": &"mate_selectivity", "cat": &"behavior", "chr": 4, "label": "Избирательность партнёра", "min": 0.0, "max": 1.0, "default": 0.4, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Половой отбор, ускоряет видообразование"},
	{"id": &"diet_preference", "cat": &"behavior", "chr": 4, "label": "Пищевое предпочтение", "min": 0.0, "max": 1.0, "default": 0.1, "loci": 2, "h": 0.5, "sigma": 0.05, "scope": "0 — растения, 1 — животные"},
	{"id": &"learning", "cat": &"behavior", "chr": 4, "label": "Обучаемость", "min": 0.0, "max": 1.0, "default": 0.4, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Длительность памяти о еде и опасностях"},
	# --- Senses (chr 5) ---------------------------------------------------------------
	{"id": &"vision_acuity", "cat": &"senses", "chr": 5, "label": "Острота зрения", "min": 0.6, "max": 1.4, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Дальность обнаружения глазами"},
	{"id": &"night_vision", "cat": &"senses", "chr": 5, "label": "Ночное зрение", "min": 0.0, "max": 1.0, "default": 0.2, "loci": 1, "h": 0.5, "sigma": 0.05, "scope": "Зрение в темноте"},
	{"id": &"smell_acuity", "cat": &"senses", "chr": 5, "label": "Обоняние", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Дальность чувства запаха"},
	{"id": &"hearing_acuity", "cat": &"senses", "chr": 5, "label": "Слух", "min": 0.6, "max": 1.6, "default": 1.0, "loci": 1, "h": 0.5, "sigma": 0.04, "scope": "Дальность слуха"},
]

const CATEGORY_LABELS := {
	&"anatomy": "Анатомия", &"color": "Окраска", &"physiology": "Физиология",
	&"life": "Жизненный цикл", &"behavior": "Поведение", &"senses": "Органы чувств",
}

static var _built := false
static var _index := {}            # trait id -> trait index
static var _locus_start := PackedInt32Array()   # trait index -> first locus index
static var _locus_trait := PackedInt32Array()   # locus index -> trait index
static var _chr_loci: Array = []    # chromosome -> Array[int] locus indices (ordered)
static var _locus_count := 0


static func _build() -> void:
	if _built:
		return
	_index.clear()
	_locus_start = PackedInt32Array()
	_locus_trait = PackedInt32Array()
	_chr_loci = []
	for c in CHROMOSOMES:
		_chr_loci.append([])
	var li := 0
	for ti in DEFS.size():
		var d: Dictionary = DEFS[ti]
		_index[d["id"]] = ti
		_locus_start.append(li)
		for k in int(d["loci"]):
			_locus_trait.append(ti)
			(_chr_loci[int(d["chr"])] as Array).append(li)
			li += 1
	_locus_count = li
	_built = true


static func count() -> int:
	return DEFS.size()


static func locus_count() -> int:
	_build()
	return _locus_count


static func index_of(id: StringName) -> int:
	_build()
	return _index.get(id, -1)


static func has(id: StringName) -> bool:
	return index_of(id) >= 0


static func def_at(i: int) -> Dictionary:
	return DEFS[i]


static func get_def(id: StringName) -> Dictionary:
	var i := index_of(id)
	return DEFS[i] if i >= 0 else {}


static func locus_start(trait_index: int) -> int:
	_build()
	return _locus_start[trait_index]


static func trait_of_locus(locus: int) -> int:
	_build()
	return _locus_trait[locus]


static func chromosome_loci(chr: int) -> Array:
	_build()
	return _chr_loci[chr]


static func ids_in_category(cat: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in DEFS:
		if d["cat"] == cat:
			out.append(d["id"])
	return out


## Real value -> normalized 0..1.
static func normalize(trait_index: int, value: float) -> float:
	var d: Dictionary = DEFS[trait_index]
	var lo := float(d["min"])
	var hi := float(d["max"])
	return clampf((value - lo) / (hi - lo), 0.0, 1.0) if hi > lo else 0.0


static func denormalize(trait_index: int, n: float) -> float:
	var d: Dictionary = DEFS[trait_index]
	return lerpf(float(d["min"]), float(d["max"]), clampf(n, 0.0, 1.0))


static func inheritance_label(trait_index: int) -> String:
	var d: Dictionary = DEFS[trait_index]
	var h := float(d["h"])
	var mode := "аддитивный"
	if h >= 0.8:
		mode = "доминантный"
	elif h <= 0.2:
		mode = "рецессивный"
	var loci := int(d["loci"])
	if loci > 1:
		mode += ", полигенный (%d локуса)" % loci if loci < 5 else ", полигенный (%d локусов)" % loci
	return mode
