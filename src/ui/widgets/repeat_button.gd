class_name RepeatButton
extends IconButton
## IconButton that repeats while held (for −/+ steppers): emits `step` once on
## a tap, and repeatedly (accelerating) while held. Emits `hold_released` when
## the finger lifts after repeating, so callers can commit the final value.
##
##   var minus := RepeatButton.make_repeat(&"minus", tr("Меньше"))
##   minus.step.connect(func(): value -= 1)

## One step requested (tap or auto-repeat tick).
signal step
## The button was released (after a tap or a hold).
signal hold_released

@export var initial_delay: float = 0.4
@export var start_interval: float = 0.14
@export var min_interval: float = 0.035

var _held := false
var _t := 0.0
var _interval := 0.14
var _repeated := false


static func make_repeat(icon_id: StringName, tooltip: String = "") -> RepeatButton:
	var b := RepeatButton.new()
	b.icon_name = icon_id
	b.tooltip_text = tooltip
	b.long_press_time = 1.0e9  # repeating replaces the long-press bubble
	return b


func _ready() -> void:
	super()
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	pressed.connect(_on_pressed)
	set_physics_process(false)


func _on_down() -> void:
	_held = true
	_repeated = false
	_t = -initial_delay
	_interval = start_interval
	set_physics_process(true)


func _on_up() -> void:
	_held = false
	set_physics_process(false)
	hold_released.emit()


func _on_pressed() -> void:
	if not _repeated:
		step.emit()


func _physics_process(delta: float) -> void:
	if not _held or disabled:
		set_physics_process(false)
		return
	_t += delta
	if _t >= _interval:
		_t = 0.0
		_repeated = true
		_interval = maxf(min_interval, _interval * 0.82)
		step.emit()
