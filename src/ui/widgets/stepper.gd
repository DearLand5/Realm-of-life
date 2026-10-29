class_name Stepper
extends HBoxContainer
## Compact numeric input: [−] value [+]. Hold a button to repeat
## (accelerating); tap the value to type it.
##
##   var s := Stepper.make(0, 30, 1, 8)           # min, max, step, value
##   s.value_committed.connect(func(v): cfg.species = int(v))
##
## Signals:
##   value_changed(value)   — every change (each step, typed value)
##   value_committed(value) — final value: tap, hold release or text entry

signal value_changed(value: float)
signal value_committed(value: float)

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var step: float = 1.0
## Decimals shown; -1 = derived from `step`.
@export var decimals: int = -1
@export var unit: String = "":
	set(v):
		unit = v
		if _field != null:
			_field.unit = v
			_field.show_value(_value)

var value: float:
	get:
		return _value
	set(v):
		set_value(v)

var _value: float = 0.0
var _minus: RepeatButton
var _plus: RepeatButton
var _field: NumberField


static func make(min_v: float, max_v: float, step_v: float, v: float, unit_text: String = "") -> Stepper:
	var s := Stepper.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.unit = unit_text
	s.set_value(v)
	return s


func _init() -> void:
	_minus = RepeatButton.make_repeat(&"minus", tr("Меньше"))
	_plus = RepeatButton.make_repeat(&"plus", tr("Больше"))
	_field = NumberField.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_minus)
	add_child(_field)
	add_child(_plus)
	_minus.step.connect(func() -> void: _apply(_value - step, false))
	_plus.step.connect(func() -> void: _apply(_value + step, false))
	_minus.hold_released.connect(func() -> void: value_committed.emit(_value))
	_plus.hold_released.connect(func() -> void: value_committed.emit(_value))
	_field.value_entered.connect(func(v: float) -> void: _apply(v, true))


func _ready() -> void:
	_field.unit = unit
	_field.decimals = decimals if decimals >= 0 else UIFormat.decimals_for_step(step)
	_field.show_value(_value)
	_refresh_buttons()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _field != null:
		_field.custom_minimum_size.x = UITheme.k(self, &"touch") * 1.6
		UITheme.override_const(self, "separation", UITheme.k(self, &"gap"))


## Sets the value (snapped, clamped) without emitting signals.
func set_value(v: float) -> void:
	_value = _snap(v)
	if _field != null:
		_field.decimals = decimals if decimals >= 0 else UIFormat.decimals_for_step(step)
		_field.show_value(_value)
	_refresh_buttons()


func _apply(v: float, commit: bool) -> void:
	var nv := _snap(v)
	var changed := not is_equal_approx(nv, _value)
	_value = nv
	_field.show_value(nv)
	_refresh_buttons()
	if changed:
		value_changed.emit(nv)
	if commit:
		value_committed.emit(nv)


func _snap(v: float) -> float:
	var x := clampf(v, min_value, max_value)
	if step > 0.0:
		x = min_value + roundf((x - min_value) / step) * step
	return clampf(x, min_value, max_value)


func _refresh_buttons() -> void:
	if _minus == null:
		return
	_minus.disabled = _value <= min_value + 1e-9
	_plus.disabled = _value >= max_value - 1e-9
