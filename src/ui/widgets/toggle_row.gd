class_name ToggleRow
extends PanelContainer
## Settings-style row: [icon] title / description ......... [switch].
## The whole row is the touch target (tap anywhere toggles).
##
##   var r := ToggleRow.make(tr("Инвертировать Y"), tr("Для камеры и обзора"), &"camera")
##   r.button_pressed = UIApp.setting("invert_y", false)
##   r.toggled.connect(func(on): UIApp.set_setting("invert_y", on))
##
## Signals: toggled(on: bool) — user change only (not when set from code).

signal toggled(on: bool)

var button_pressed: bool:
	get:
		return _switch.button_pressed if _switch != null else false
	set(v):
		if _switch != null:
			_switch.set_pressed_no_signal(v)

var title: String = "":
	set(v):
		title = v
		if _title != null:
			_title.text = v
var description: String = "":
	set(v):
		description = v
		if _desc != null:
			_desc.text = v
			_desc.visible = v != ""
var icon_name: StringName = &""
var disabled: bool = false:
	set(v):
		disabled = v
		if _switch != null:
			_switch.disabled = v
		modulate.a = 0.5 if v else 1.0

const TAP_SLOP := 16.0

var _switch: CheckButton
var _title: Label
var _desc: Label
var _press_pos := Vector2(-1, -1)


static func make(title_text: String, desc: String = "", icon_id: StringName = &"", on: bool = false) -> ToggleRow:
	var r := ToggleRow.new()
	r.title = title_text
	r.description = desc
	r.icon_name = icon_id
	r.button_pressed = on
	return r


func _init() -> void:
	theme_type_variation = &"ClearPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc = Label.new()
	_desc.theme_type_variation = &"DimLabel"
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	v.add_child(_desc)
	h.add_child(v)
	_switch = CheckButton.new()
	_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_switch.toggled.connect(func(on: bool) -> void: toggled.emit(on))
	h.add_child(_switch)


func _ready() -> void:
	_title.text = title
	_desc.text = description
	_desc.visible = description != ""
	if icon_name != &"":
		var iv := IconView.make(icon_name, UITheme.k(self, &"icon"), &"text_dim")
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var h := get_child(0)
		h.add_child(iv)
		h.move_child(iv, 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _switch != null:
		custom_minimum_size.y = UITheme.k(self, &"touch")
		(get_child(0) as HBoxContainer).add_theme_constant_override("separation", UITheme.k(self, &"gap_large"))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or disabled:
		return
	if mb.pressed:
		_press_pos = mb.position
	elif _press_pos.x >= 0.0 and mb.position.distance_to(_press_pos) < TAP_SLOP * UITheme.scale_of(self):
		_press_pos = Vector2(-1, -1)
		_switch.button_pressed = not _switch.button_pressed
		accept_event()
