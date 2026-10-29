class_name NewWorldDialog
extends ModalDialog
## «Новый мир»: world generation settings + choice of the player's species.
## On create: Game.goto_scene(SCENE_WORLD, {"new_world": config, "player_species": [uids]}).
##
## config keys (merge onto WorldConfig.defaults() on the world side):
##   name, seed:int, size:float (m), size_preset: "small"|"medium"|"large",
##   relief, vegetation, biome_diversity: 0..1, temperature_offset: °C,
##   moisture_offset: −0.5..0.5, procedural_species:int, rivers:bool

## Emitted with the final payload instead of changing scene when `dry_run`.
signal world_requested(payload: Dictionary)

const SIZES := {"small": 512.0, "medium": 1024.0, "large": 2048.0}

## For previews/tests: library entries to show instead of SpeciesLibrary.list_entries().
var library_entries: Variant = null
## Do not change scene; only emit world_requested.
var dry_run: bool = false

var config: Dictionary = default_config()
var _picked: Dictionary = {}  # uid → true
var _name_edit: LineEdit
var _seed_edit: LineEdit


static func default_config() -> Dictionary:
	return {
		"name": TranslationServer.translate("Новый мир"), "seed": randi() % 1000000000, "size": SIZES["medium"],
		"size_preset": "medium", "relief": 0.5, "vegetation": 0.6, "biome_diversity": 0.6,
		"temperature_offset": 0.0, "moisture_offset": 0.0, "procedural_species": 8, "rivers": true,
	}


func _ready() -> void:
	title = tr("Новый мир")
	icon_name = &"globe"
	size_class = SizeClass.LARGE
	_build()
	add_button(&"cancel", tr("Отмена"))
	var create := add_button(&"create", tr("Создать мир"), &"AccentButton", &"check", false)
	create.pressed.connect(_create)
	super()


func _build() -> void:
	var cols := ResponsiveBox.new()
	UITheme.override_const(cols, "separation", 28)
	content.add_child(cols)
	var left := MenuUI.column()
	var right := MenuUI.column()
	cols.add_child(left)
	cols.add_child(right)
	# --- Basics
	left.add_child(MenuUI.section(tr("Основное"), &"globe"))
	_name_edit = LineEdit.new()
	_name_edit.text = str(config["name"])
	_name_edit.max_length = 40
	_name_edit.text_changed.connect(func(t: String) -> void: config["name"] = t.strip_edges())
	left.add_child(MenuUI.field(tr("Название"), _name_edit))
	var seed_row := HBoxContainer.new()
	UITheme.override_const(seed_row, "separation", 8)
	_seed_edit = LineEdit.new()
	_seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text = str(config["seed"])
	_seed_edit.text_changed.connect(_on_seed_text)
	seed_row.add_child(_seed_edit)
	var dice := IconButton.make(&"dice", tr("Случайный"), tr("Новый случайный сид"))
	dice.pressed.connect(func() -> void:
		config["seed"] = randi() % 1000000000
		_seed_edit.text = str(config["seed"]))
	seed_row.add_child(dice)
	left.add_child(MenuUI.field(tr("Сид (зерно генерации)"), seed_row))
	var size_pick := EnumPicker.make(tr("Размер"), [
		{"id": "small", "label": tr("Малый"), "description": tr("0,5 км — быстро даже на слабых телефонах")},
		{"id": "medium", "label": tr("Средний"), "description": tr("1 км — рекомендуется")},
		{"id": "large", "label": tr("Большой"), "description": tr("2 км — для мощных устройств")},
	], config["size_preset"], EnumPicker.Mode.SEGMENTED)
	size_pick.selected.connect(func(id: Variant) -> void:
		config["size_preset"] = str(id)
		config["size"] = SIZES[str(id)])
	left.add_child(size_pick)
	# --- Life
	left.add_child(MenuUI.section(tr("Жизнь"), &"paw"))
	var procedural := Stepper.make(0, 40, 1, float(config["procedural_species"]))
	procedural.value_changed.connect(func(v: float) -> void: config["procedural_species"] = int(v))
	left.add_child(MenuUI.field(tr("Случайные виды"), procedural))
	left.add_child(_species_picker())
	# --- Landscape
	right.add_child(MenuUI.section(tr("Ландшафт и климат"), &"mountain"))
	right.add_child(_slider(tr("Рельеф"), "relief", 0.0, 1.0, 0.05, "%", 100.0))
	right.add_child(_slider(tr("Растительность"), "vegetation", 0.0, 1.0, 0.05, "%", 100.0))
	right.add_child(_slider(tr("Разнообразие биомов"), "biome_diversity", 0.0, 1.0, 0.05, "%", 100.0))
	right.add_child(_slider(tr("Температура"), "temperature_offset", -15.0, 15.0, 0.5, "°C", 1.0))
	right.add_child(_slider(tr("Влажность"), "moisture_offset", -0.5, 0.5, 0.05, "%", 100.0))
	var rivers := ToggleRow.make(tr("Реки"), tr("Русла рек и озёра"), &"drop", bool(config["rivers"]))
	rivers.toggled.connect(func(on: bool) -> void: config["rivers"] = on)
	right.add_child(rivers)


func _slider(label: String, key: String, lo: float, hi: float, step_v: float, unit_text: String, factor: float) -> ParamSlider:
	var s := ParamSlider.make(label, lo, hi, step_v, float(config[key]), unit_text)
	s.display_factor = factor
	s.value_changed.connect(func(v: float) -> void: config[key] = v)
	return s


func _species_picker() -> Control:
	var v := VBoxContainer.new()
	UITheme.override_const(v, "separation", 4)
	v.add_child(MenuUI.section(tr("Ваши виды"), &"library"))
	var entries: Array = library_entries if library_entries is Array else SpeciesLibrary.list_entries()
	if entries.is_empty():
		v.add_child(MenuUI.dim_label(tr("В библиотеке пока нет видов. Создайте свой вид в редакторе — его можно будет выпустить в мир.")))
		return v
	v.add_child(MenuUI.dim_label(tr("Отметьте виды, которые появятся в мире")))
	for e in entries:
		var uid := str(e.get("uid", ""))
		var cb := CheckBox.new()
		cb.text = ("★ " if bool(e.get("favorite", false)) else "") + str(e.get("name", "?"))
		cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				_picked[uid] = true
			else:
				_picked.erase(uid))
		v.add_child(cb)
	return v


func _on_seed_text(t: String) -> void:
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != t:
		var caret := _seed_edit.caret_column
		_seed_edit.text = digits
		_seed_edit.caret_column = mini(caret, digits.length())
	config["seed"] = int(digits) if digits != "" else 0


func payload() -> Dictionary:
	var cfg := config.duplicate(true)
	if str(cfg["name"]) == "":
		cfg["name"] = tr("Новый мир")
	return {"new_world": cfg, "player_species": _picked.keys()}


func _create() -> void:
	var p := payload()
	world_requested.emit(p)
	if dry_run or UIApp.goto_scene("SCENE_WORLD", p):
		close(&"create")
