class_name ParamSlider
extends VBoxContainer
## Labelled parameter slider for touch: a title row with the exact value
## (tap to type it, numeric keyboard), and a [−] slider [+] row. Values snap
## to `step`; −/+ repeat while held.
##
##   var s := ParamSlider.make(tr("Рельеф"), 0.0, 1.0, 0.05, 0.5)
##   s.unit = "%" ; s.display_factor = 100.0      # shows 50 % for 0.5
##   s.help_term = "нагрузка на крыло"           # adds a (?) glossary button
##   s.value_committed.connect(func(v): cfg.relief = v)
##
## Signals:
##   value_changed(value)   — continuously while dragging / stepping
##   value_committed(value) — on release: drag end, stepper release, text entry,
##                            keyboard arrow. Apply expensive changes here.

signal value_changed(value: float)
signal value_committed(value: float)

@export var label_text: String = "":
	set(v):
		label_text = v
		if _label != null:
			_label.text = v
@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var step: float = 0.01
## Unit suffix shown after the number ("°C", "м", "%").
@export var unit: String = "":
	set(v):
		unit = v
		if _field != null:
			_field.unit = v
			_sync()
## Displayed number = value × display_factor (e.g. 100 for percent).
@export var display_factor: float = 1.0
## Decimals of the displayed number; -1 = derived from step × display_factor.
@export var decimals: int = -1
## Exponential slider response (for wide ranges like 0.01..1000).
@export var exponential: bool = false
## Glossary term for the (?) button; empty = no button.
@export var help_term: String = "":
	set(v):
		help_term = v
		if _help != null:
			_help.term = v
			_help.visible = v != ""

var value: float:
	get:
		return _value
	set(v):
		set_value(v)

var _value: float = 0.0
var _dragging := false
var _label: Label
var _field: NumberField
var _slider: HSlider
var _minus: RepeatButton
var _plus: RepeatButton
var _help: HelpButton


static func make(title: String, min_v: float, max_v: float, step_v: float, v: float, unit_text: String = "") -> ParamSlider:
	var s := ParamSlider.new()
	s.label_text = title
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.unit = unit_text
	s.set_value(v)
	return s


func _init() -> void:
	var top := HBoxContainer.new()
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help = HelpButton.for_term("")
	_help.visible = false
	_field = NumberField.new()
	top.add_child(_label)
	top.add_child(_help)
	top.add_child(_field)
	var row := HBoxContainer.new()
	_minus = RepeatButton.make_repeat(&"minus", tr("Меньше"))
	_plus = RepeatButton.make_repeat(&"plus", tr("Больше"))
	_minus.theme_type_variation = &"FlatButton"
	_plus.theme_type_variation = &"FlatButton"
	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_ALL
	row.add_child(_minus)
	row.add_child(_slider)
	row.add_child(_plus)
	add_child(top)
	add_child(row)
	_slider.value_changed.connect(_on_slider)
	_slider.drag_ended.connect(_on_drag_ended)
	_slider.gui_input.connect(_on_slider_input)
	_minus.step.connect(func() -> void: _apply(_value - step, true, false))
	_plus.step.connect(func() -> void: _apply(_value + step, true, false))
	_minus.hold_released.connect(func() -> void: value_committed.emit(_value))
	_plus.hold_released.connect(func() -> void: value_committed.emit(_value))
	_field.value_entered.connect(func(v: float) -> void: _apply(v / maxf(display_factor, 1e-9), true, true))


func _ready() -> void:
	_label.text = label_text
	_help.term = help_term
	_help.visible = help_term != ""
	_configure()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _field != null:
		var t := UITheme.k(self, &"touch")
		_field.custom_minimum_size = Vector2(t * 2.3, 0)
		_slider.custom_minimum_size.y = t
		UITheme.override_const(self, "separation", 0)


func _configure() -> void:
	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = 0.0  # we snap ourselves (keeps exp_edit smooth)
	_slider.exp_edit = exponential and min_value > 0.0
	_field.unit = unit
	_field.decimals = decimals if decimals >= 0 else UIFormat.decimals_for_step(step * display_factor)
	_sync()


## Changes the range at runtime (keeps the value inside it). No signals.
func set_range(min_v: float, max_v: float, step_v: float = -1.0) -> void:
	min_value = min_v
	max_value = max_v
	if step_v > 0.0:
		step = step_v
	_value = _snap(_value)
	if _slider != null:
		_configure()


## Sets the value (snapped, clamped) without emitting signals.
func set_value(v: float) -> void:
	_value = _snap(v)
	if _slider != null and is_inside_tree():
		_sync()


func _sync() -> void:
	if _slider == null:
		return
	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.set_value_no_signal(_value)
	_field.show_value(_value * display_factor)
	_minus.disabled = _value <= min_value + 1e-9
	_plus.disabled = _value >= max_value - 1e-9


func _apply(v: float, changed: bool, commit: bool) -> void:
	var nv := _snap(v)
	var differs := not is_equal_approx(nv, _value)
	_value = nv
	_sync()
	if changed and differs:
		value_changed.emit(nv)
	if commit:
		value_committed.emit(nv)


func _snap(v: float) -> float:
	var x := clampf(v, min_value, max_value)
	if step > 0.0:
		x = min_value + roundf((x - min_value) / step) * step
	return clampf(x, min_value, max_value)


func _on_slider(v: float) -> void:
	_apply(v, true, not _dragging)


func _on_slider_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
		else:
			_end_drag.call_deferred()


func _on_drag_ended(_changed: bool) -> void:
	_end_drag()


func _end_drag() -> void:
	if _dragging:
		_dragging = false
		value_committed.emit(_value)
