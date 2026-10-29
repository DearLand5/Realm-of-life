class_name NumberField
extends LineEdit
## Numeric text field for precise entry on phones: numeric virtual keyboard,
## accepts "," or "." decimals, shows the unit when not editing ("12,5 °C"),
## reverts invalid input. Used by ParamSlider and Stepper.

## A valid number was entered (Enter or focus loss). Not emitted by show_value().
signal value_entered(value: float)

@export var decimals: int = 2
@export var unit: String = ""

var _value: float = 0.0


func _init() -> void:
	virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_all_on_focus = true
	context_menu_enabled = false
	text_submitted.connect(func(_t: String) -> void: _commit_text(); release_focus())
	focus_entered.connect(func() -> void: text = UIFormat.number(_value, decimals))
	focus_exited.connect(_commit_text)


## Displays `v` without emitting.
func show_value(v: float) -> void:
	_value = v
	if not has_focus():
		text = format_value(v)


func format_value(v: float) -> String:
	var s := UIFormat.number(v, decimals)
	return s + ((" " if not unit.begins_with("%") else "") + unit if unit != "" else "")


func _commit_text() -> void:
	var parsed: Variant = UIFormat.parse(text.trim_suffix(unit).strip_edges())
	if parsed == null:
		text = format_value(_value)
		return
	value_entered.emit(float(parsed))
	if not has_focus():
		text = format_value(_value)
