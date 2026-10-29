class_name SafeArea
extends MarginContainer
## Container that keeps its children out of notches, rounded corners, camera
## cut-outs and system bars. Margins = OS safe-area insets (converted from
## screen pixels to canvas units) + cut-outs touching an edge + `extra_margin`.
##
##   var safe := SafeArea.new()            # full-rect by default
##   add_child(safe); safe.add_child(my_hud)
##   SafeArea.insets_for(control)          # Vector4(left, top, right, bottom), canvas units
##   SafeArea.debug_insets = Vector4(0, 44, 0, 34)   # simulate a notch in previews

## Minimum margin on every side (canvas px at ui scale 1; scaled with the theme).
@export var extra_margin: float = 0.0
## Ignore specific edges (e.g. a bottom sheet that should run under the home bar).
@export var use_left: bool = true
@export var use_top: bool = true
@export var use_right: bool = true
@export var use_bottom: bool = true

## Simulated insets for previews/tests (canvas units, x=left y=top z=right w=bottom).
## Added on top of the real insets; zero by default.
static var debug_insets := Vector4.ZERO


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	get_viewport().size_changed.connect(_update)
	_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		_update.call_deferred()


func _update() -> void:
	if not is_inside_tree():
		return
	var ins := insets_for(self)
	var e := extra_margin * UITheme.scale_of(self)
	_set_margin("margin_left", ins.x + e if use_left else e)
	_set_margin("margin_top", ins.y + e if use_top else e)
	_set_margin("margin_right", ins.z + e if use_right else e)
	_set_margin("margin_bottom", ins.w + e if use_bottom else e)


func _set_margin(name: StringName, v: float) -> void:
	var iv := int(ceilf(v))
	if get_theme_constant(name) != iv:
		add_theme_constant_override(name, iv)


## Insets (left, top, right, bottom) in the canvas units of `node`'s viewport.
static func insets_for(node: Node) -> Vector4:
	var vp := node.get_viewport() if node != null and node.is_inside_tree() else null
	var out := debug_insets
	if vp == null:
		return out
	var real := screen_insets_px()
	if real == Vector4.ZERO:
		return out
	var scale := 1.0
	if vp is Window:
		scale = absf((vp as Window).get_final_transform().get_scale().x)
	scale = maxf(scale, 0.0001)
	return out + real / scale


## Insets in physical window pixels from the OS safe area and display cut-outs.
## Zero on desktop windows (their "safe area" is the work area, not a notch).
static func screen_insets_px() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win_pos := Vector2(DisplayServer.window_get_position())
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var ins := Vector4.ZERO
	if safe.size.x > 0.0 and safe.size.y > 0.0:
		ins.x = maxf(0.0, safe.position.x - win_pos.x)
		ins.y = maxf(0.0, safe.position.y - win_pos.y)
		ins.z = maxf(0.0, win_pos.x + win_size.x - safe.end.x)
		ins.w = maxf(0.0, win_pos.y + win_size.y - safe.end.y)
	for cut in DisplayServer.get_display_cutouts():
		var r := Rect2(cut)
		r.position -= win_pos
		# Assign each cut-out to the nearest window edge.
		var d := [r.position.x, r.position.y, win_size.x - r.end.x, win_size.y - r.end.y]
		var edge := 0
		for i in 4:
			if d[i] < d[edge]:
				edge = i
		match edge:
			0: ins.x = maxf(ins.x, r.end.x)
			1: ins.y = maxf(ins.y, r.end.y)
			2: ins.z = maxf(ins.z, win_size.x - r.position.x)
			3: ins.w = maxf(ins.w, win_size.y - r.position.y)
	return ins
