class_name TouchButton
extends Control
## Round on-screen game button for touch HUDs (jump, eat, attack...).
## Multi-touch safe (tracks its own finger index), so it works while another
## finger holds the joystick. Optionally drives an InputMap action, so game
## code can read `Input.is_action_pressed(&"jump")` for touch and keyboard alike.
##
##   var b := TouchButton.make(&"jump", &"jump", tr("Прыжок"))
##   b.tapped.connect(...)          # short press
##   b.held.connect(...)            # still down after hold_time
##   b.toggle_mode = true           # e.g. fly_toggle → toggled(on)
##
## Signals: pressed, released, tapped, held, toggled(on).
## The finger may slide off while holding (keeps pressed until lifted), which
## is what players expect for sprint/hold buttons.

signal pressed
signal released
signal tapped
signal held
signal toggled(on: bool)

@export var icon_name: StringName = &"info":
	set(v):
		icon_name = v
		queue_redraw()
## Short caption under the icon (optional; keep 1 word).
@export var label: String = "":
	set(v):
		label = v
		queue_redraw()
## InputMap action pressed/released with the button (empty = none).
@export var action: StringName = &""
@export var toggle_mode: bool = false
@export var hold_time: float = 0.45
## Shape: round (default) or rounded square.
@export var round_shape: bool = true

var is_pressed: bool = false
var toggled_on: bool = false:
	set(v):
		toggled_on = v
		queue_redraw()
var disabled: bool = false:
	set(v):
		disabled = v
		if v and is_pressed:
			_finish(false)
		queue_redraw()

var _touch := -1
var _t_down := 0.0
var _held_fired := false


static func make(icon_id: StringName, action_name: StringName = &"", caption: String = "") -> TouchButton:
	var b := TouchButton.new()
	b.icon_name = icon_id
	b.action = action_name
	b.label = caption
	return b


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(52, 52)
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st == null:
		return
	if st.pressed and _touch < 0 and not disabled:
		_touch = st.index
		is_pressed = true
		_t_down = 0.0
		_held_fired = false
		set_process(true)
		if action != &"" and InputMap.has_action(action):
			Input.action_press(action)
		pressed.emit()
		queue_redraw()
		accept_event()
	elif not st.pressed and st.index == _touch:
		_finish(true)
		accept_event()


func _finish(fire: bool) -> void:
	_touch = -1
	is_pressed = false
	set_process(false)
	if action != &"" and InputMap.has_action(action):
		Input.action_release(action)
	released.emit()
	if fire and not _held_fired:
		tapped.emit()
		if toggle_mode:
			toggled_on = not toggled_on
			toggled.emit(toggled_on)
	queue_redraw()


func _process(delta: float) -> void:
	_t_down += delta
	if not _held_fired and _t_down >= hold_time:
		_held_fired = true
		held.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and is_pressed:
		_finish(false)
	elif what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var sc := UITheme.scale_of(self)
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var on := is_pressed or toggled_on
	var bg := UITheme.color(self, &"accent") if on else UITheme.color(self, &"panel")
	var a := 0.4 if disabled else 1.0
	bg.a = (0.95 if on else 0.62) * a
	var border := UITheme.color(self, &"accent") if toggled_on else UITheme.color(self, &"border_strong")
	if round_shape:
		draw_circle(c + Vector2(0, 2.0 * sc), r - 1.0, Color(0, 0, 0, 0.22 * a), true, -1.0, true)
		draw_circle(c, r - 1.0, bg, true, -1.0, true)
		draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(border, border.a * a * 1.3), maxf(1.5, 2.0 * sc), true)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(maxi(1, int(2 * sc)))
		sb.set_corner_radius_all(int(r * 0.45))
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var fg := UITheme.color(self, &"accent_text") if on else UITheme.color(self, &"text")
	fg.a *= a
	var has_label := label != "" and r > 34.0 * sc
	var isz := r * (0.78 if not has_label else 0.66)
	var icy := c.y - (r * 0.14 if has_label else 0.0)
	Icons.draw(self, icon_name, Rect2(Vector2(c.x - isz * 0.5, icy - isz * 0.5), Vector2(isz, isz)), fg)
	if has_label:
		var font := get_theme_default_font()
		var fs := UITheme.font_size(self, &"tiny")
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + r * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
