class_name HsvPlane
extends Control
## Touch surface of ColorSwatchPicker: a saturation/value square or a hue
## strip. Handles ScreenTouch/ScreenDrag only (mouse arrives as emulated
## touch), tracks one finger by index.
##
## Signals: changed() while dragging, released() when the finger lifts.

signal changed
signal released

enum Mode { SV, HUE }

var mode: Mode = Mode.SV
var hue: float = 0.0:
	set(v):
		hue = v
		queue_redraw()
var sat: float = 1.0:
	set(v):
		sat = v
		queue_redraw()
var val: float = 1.0:
	set(v):
		val = v
		queue_redraw()

var _touch := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null:
		if st.pressed and _touch < 0:
			_touch = st.index
			_pick(st.position)
			accept_event()
		elif not st.pressed and st.index == _touch:
			_touch = -1
			released.emit()
			accept_event()
		return
	var sd := event as InputEventScreenDrag
	if sd != null and sd.index == _touch:
		_pick(sd.position)
		accept_event()


func _pick(pos: Vector2) -> void:
	var r := _inner_rect()
	var u := clampf((pos.x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
	var v := clampf((pos.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)
	if mode == Mode.SV:
		sat = u
		val = 1.0 - v
	else:
		hue = u
	changed.emit()


func _inner_rect() -> Rect2:
	var m := 10.0 * UITheme.scale_of(self)
	return Rect2(Vector2(m, m * 0.5), size - Vector2(m * 2.0, m))


func _draw() -> void:
	var r := _inner_rect()
	if mode == Mode.SV:
		var n := 8
		for iy in n:
			for ix in n:
				var u0 := float(ix) / n
				var u1 := float(ix + 1) / n
				var v0 := float(iy) / n
				var v1 := float(iy + 1) / n
				var pts := PackedVector2Array([r.position + r.size * Vector2(u0, v0), r.position + r.size * Vector2(u1, v0),
					r.position + r.size * Vector2(u1, v1), r.position + r.size * Vector2(u0, v1)])
				var cols := PackedColorArray([Color.from_hsv(hue, u0, 1.0 - v0), Color.from_hsv(hue, u1, 1.0 - v0),
					Color.from_hsv(hue, u1, 1.0 - v1), Color.from_hsv(hue, u0, 1.0 - v1)])
				draw_polygon(pts, cols)
		var p := r.position + r.size * Vector2(sat, 1.0 - val)
		_marker(p, Color.from_hsv(hue, sat, val))
	else:
		var n := 24
		for i in n:
			var u0 := float(i) / n
			var u1 := float(i + 1) / n
			var pts := PackedVector2Array([Vector2(r.position.x + r.size.x * u0, r.position.y), Vector2(r.position.x + r.size.x * u1, r.position.y),
				Vector2(r.position.x + r.size.x * u1, r.end.y), Vector2(r.position.x + r.size.x * u0, r.end.y)])
			var c0 := Color.from_hsv(u0, 0.85, 0.95)
			var c1 := Color.from_hsv(u1, 0.85, 0.95)
			draw_polygon(pts, PackedColorArray([c0, c1, c1, c0]))
		_marker(Vector2(r.position.x + r.size.x * hue, r.get_center().y), Color.from_hsv(hue, 0.85, 0.95))
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.set_border_width_all(maxi(1, int(UITheme.scale_of(self))))
	border.border_color = UITheme.color(self, &"border_strong")
	draw_style_box(border, r)


func _marker(p: Vector2, c: Color) -> void:
	var rad := 11.0 * UITheme.scale_of(self)
	draw_circle(p, rad + 2.0, Color(0, 0, 0, 0.45), true, -1.0, true)
	draw_circle(p, rad, Color.WHITE, true, -1.0, true)
	draw_circle(p, rad - 3.0, c, true, -1.0, true)
