class_name ColorSwatchPicker
extends VBoxContainer
## Colour choice for touch: big preset swatches (+ recently used), and an HSV
## picker (saturation/value square + hue strip) with hex entry.
##
##   var cp := ColorSwatchPicker.new()
##   cp.color = Color("#7a9a3a")
##   cp.color_committed.connect(func(c): covering.color = c)
##
## Signals:
##   color_changed(color)   — continuously while dragging in the HSV picker
##   color_committed(color) — swatch tap, finger lifted, hex entered

signal color_changed(color: Color)
signal color_committed(color: Color)

## Nature-leaning presets: skins, furs, feathers, scales, warning colours.
const PRESETS := ["#f2efe6", "#c9b48a", "#a07850", "#6b4a2e", "#3b2a1e", "#1c1a18",
	"#7a9a3a", "#3f6b2f", "#2f8f7a", "#3a6fa8", "#6c4f9e", "#b0487a",
	"#d8402f", "#e8862c", "#f2c641", "#9aa6a8", "#55606b", "#e8b7a3"]
const MAX_RECENT := 6

static var _recent: Array[Color] = []

var color: Color = Color("#7a9a3a"):
	set(v):
		color = v
		_sync_from_color()
## Show the HSV picker below the swatches (else only swatches).
var show_custom: bool = true

var _preview: ColorRect
var _hex: LineEdit
var _swatches: HFlowContainer
var _sv: HsvPlane
var _hue: HsvPlane


func _init() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	_preview = ColorRect.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_preview)
	_hex = LineEdit.new()
	_hex.max_length = 7
	_hex.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hex.text_submitted.connect(func(_t: String) -> void: _on_hex(); _hex.release_focus())
	_hex.focus_exited.connect(_on_hex)
	top.add_child(_hex)
	_swatches = HFlowContainer.new()
	add_child(_swatches)
	_sv = HsvPlane.new()
	_sv.mode = HsvPlane.Mode.SV
	_hue = HsvPlane.new()
	_hue.mode = HsvPlane.Mode.HUE
	add_child(_sv)
	add_child(_hue)
	for plane in [_sv, _hue]:
		(plane as HsvPlane).changed.connect(_on_plane_changed)
		(plane as HsvPlane).released.connect(func() -> void: _commit(color))


func _ready() -> void:
	_sv.visible = show_custom
	_hue.visible = show_custom
	_rebuild_swatches()
	_sync_from_color()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _sv != null:
		var t := UITheme.k(self, &"touch")
		var sc := UITheme.scale_of(self)
		_preview.custom_minimum_size = Vector2(t * 1.5, t)
		_hex.custom_minimum_size.x = t * 2.6
		_sv.custom_minimum_size = Vector2(0, 170.0 * sc)
		_hue.custom_minimum_size = Vector2(0, t * 0.8)
		UITheme.override_const(self, "separation", UITheme.k(self, &"gap_large"))
		UITheme.override_const(_swatches, "h_separation", UITheme.k(self, &"gap"))
		UITheme.override_const(_swatches, "v_separation", UITheme.k(self, &"gap"))
		_rebuild_swatches()


func _rebuild_swatches() -> void:
	if _swatches == null:
		return
	for c in _swatches.get_children():
		c.queue_free()
	var cols: Array[Color] = []
	for h in PRESETS:
		cols.append(Color(str(h)))
	for rc in _recent:
		if not cols.any(func(x: Color) -> bool: return x.is_equal_approx(rc)):
			cols.append(rc)
	var t := UITheme.k(self, &"touch")
	for c in cols:
		var sw := Swatch.new()
		sw.swatch_color = c
		sw.custom_minimum_size = Vector2(t, t)
		sw.picked.connect(func() -> void:
			color = c
			_commit(c))
		_swatches.add_child(sw)
	_mark_selected()


func _mark_selected() -> void:
	for sw in _swatches.get_children():
		(sw as Swatch).selected = (sw as Swatch).swatch_color.is_equal_approx(color)


func _sync_from_color() -> void:
	if _sv == null:
		return
	_preview.color = color
	if not _hex.has_focus():
		_hex.text = "#" + color.to_html(false)
	if color.s > 0.01:
		_sv.hue = color.h
		_hue.hue = color.h
	_sv.sat = color.s
	_sv.val = color.v
	_mark_selected()


func _on_plane_changed() -> void:
	_sv.hue = _hue.hue
	var c := Color.from_hsv(_hue.hue, _sv.sat, _sv.val)
	color = c
	_sv.hue = _hue.hue
	color_changed.emit(c)


func _on_hex() -> void:
	var t := _hex.text.strip_edges()
	if not t.begins_with("#"):
		t = "#" + t
	if Color.html_is_valid(t):
		color = Color.html(t)
		_commit(color)
	else:
		_hex.text = "#" + color.to_html(false)


func _commit(c: Color) -> void:
	_recent = _recent.filter(func(x: Color) -> bool: return not x.is_equal_approx(c))
	_recent.push_front(c)
	if _recent.size() > MAX_RECENT:
		_recent.resize(MAX_RECENT)
	color_committed.emit(c)


## One tappable colour tile (private helper of the picker).
class Swatch:
	extends Control
	signal picked
	var swatch_color := Color.WHITE
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		var st := event as InputEventScreenTouch
		if st != null and not st.pressed and Rect2(Vector2.ZERO, size).has_point(st.position):
			picked.emit()
			accept_event()

	func _draw() -> void:
		var sc := UITheme.scale_of(self)
		var sb := StyleBoxFlat.new()
		sb.bg_color = swatch_color
		sb.set_corner_radius_all(int(12 * sc))
		sb.anti_aliasing = true
		sb.border_color = UITheme.color(self, &"accent") if selected else UITheme.color(self, &"border")
		sb.set_border_width_all(int(3 * sc) if selected else maxi(1, int(sc)))
		draw_style_box(sb, Rect2(Vector2.ZERO, size).grow(-2.0 * sc))
		if selected:
			var mark := Color.BLACK if swatch_color.get_luminance() > 0.55 else Color.WHITE
			Icons.draw(self, &"check", Rect2(size * 0.25, size * 0.5), mark, 1.3)
