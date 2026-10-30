class_name ModeSenses
extends EditorMode
## «Чувства»: eyes (with the field of view drawn on the stage), ears, nose,
## whiskers, antennae and sensors; the resulting SenseProfile is summarised.

var _summary: VBoxContainer


func build() -> void:
	add_quick_add(["eye_camera", "eye_predator", "eye_prey", "eye_compound", "ear_external", "nose", "whiskers", "sensor_electro"])
	var tg := ToggleRow.make(tr("Показывать поле зрения"), tr("Полупрозрачные веера глаз на сцене"), &"eye", ctx.show_fov)
	tg.toggled.connect(func(on: bool) -> void: ctx.set_show_fov(on))
	add_child(tg)
	_summary = VBoxContainer.new()
	var c := EditorUI.section(tr("Что воспринимает организм"), &"observer", true)
	c.content.add_child(_summary)
	add_child(c)
	_fill_summary()
	add_part_chips([&"eye", &"ear", &"nose", &"whisker", &"sensor", &"antenna"], tr("Органы чувств"))
	add_selected_panel()


func on_live() -> void:
	_fill_summary()


func _fill_summary() -> void:
	if _summary == null or not is_instance_valid(_summary):
		return
	for ch in _summary.get_children():
		_summary.remove_child(ch)
		EditorUI.dispose(ch)
	var sp := ctx.doc.phenotype.senses
	if sp.eye_count == 0:
		_summary.add_child(EditorUI.kv(tr("Зрение"), tr("нет глаз")))
	else:
		_summary.add_child(EditorUI.kv(tr("Зрение"), tr("до %s м") % UIFormat.number(sp.vision_range, 0) + (tr(" (свет/тень)") if sp.light_only else "")))
		_summary.add_child(EditorUI.kv(tr("Поле зрения"), "%d° (бинокулярное %d°)" % [int(sp.vision_fov), int(sp.binocular)]))
		_summary.add_child(EditorUI.kv(tr("Острота / ночью / цвет"), "%d%% / %d%% / %d%%" % [int(sp.acuity * 100.0), int(sp.night_vision * 100.0), int(sp.color_vision * 100.0)]))
	_summary.add_child(EditorUI.kv(tr("Обоняние"), tr("до %s м") % UIFormat.number(sp.smell_range, 0)))
	_summary.add_child(EditorUI.kv(tr("Слух"), tr("до %s м") % UIFormat.number(sp.hearing_range, 0)))
	_summary.add_child(EditorUI.kv(tr("Осязание"), tr("%s м") % UIFormat.number(sp.touch_range, 2)))
	_summary.add_child(EditorUI.kv(tr("Вибрации"), tr("%s м") % UIFormat.number(sp.vibration_range, 0)))
	if sp.electro_range > 0.0:
		_summary.add_child(EditorUI.kv(tr("Электрочувство"), tr("%s м") % UIFormat.number(sp.electro_range, 0)))
	if sp.thermal_range > 0.0:
		_summary.add_child(EditorUI.kv(tr("Тепловое чувство"), tr("%s м") % UIFormat.number(sp.thermal_range, 0)))
	if sp.magnetic:
		_summary.add_child(EditorUI.kv(tr("Магнитное чувство"), tr("есть")))
