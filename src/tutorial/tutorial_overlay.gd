extends PanelContainer
## Interactive tutorial hint card for one scene (editor or world). Shows the
## current step; advances when the step's event arrives; can be hidden or
## disabled for good (setting "show_tutorial").

var scene_id: StringName = &"world"
var _steps: Array = []
var _index: int = 0
var _title: Label
var _body: Label


func setup(scene: StringName) -> void:
	scene_id = scene
	_steps = TutorialSteps.for_scene(scene)
	var done: Array = UIApp.setting("tutorial_done", []) if UIApp.setting("tutorial_done", []) is Array else []
	while _index < _steps.size() and done.has(str(_steps[_index]["id"])):
		_index += 1
	theme_type_variation = &"CardPanel"
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 8
	offset_top = 96
	custom_minimum_size.x = 340
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = &"AccentLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	var hide_btn := IconButton.make(&"close", "", tr("Скрыть обучение"), &"FlatButton")
	hide_btn.pressed.connect(func() -> void: visible = false)
	head.add_child(hide_btn)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 320
	box.add_child(_body)
	var row := HBoxContainer.new()
	box.add_child(row)
	var skip := Button.new()
	skip.text = tr("Пропустить шаг")
	skip.theme_type_variation = &"FlatButton"
	skip.pressed.connect(func() -> void: _advance())
	row.add_child(skip)
	var off := Button.new()
	off.text = tr("Отключить обучение")
	off.theme_type_variation = &"FlatButton"
	off.pressed.connect(func() -> void:
		UIApp.set_setting("show_tutorial", false)
		queue_free())
	row.add_child(off)
	_show()


func on_event(id: StringName) -> void:
	if _index < _steps.size() and _steps[_index]["event"] == id:
		_advance()


func _advance() -> void:
	if _index >= _steps.size():
		return
	var done: Array = UIApp.setting("tutorial_done", []) if UIApp.setting("tutorial_done", []) is Array else []
	done = done.duplicate()
	done.append(str(_steps[_index]["id"]))
	UIApp.set_setting("tutorial_done", done)
	_index += 1
	_show()


func _show() -> void:
	if _index >= _steps.size():
		visible = false
		return
	var s: Dictionary = _steps[_index]
	_title.text = tr(s["title"])
	_body.text = tr(s["body"])
