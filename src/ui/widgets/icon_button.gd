class_name IconButton
extends Button
## Finger-sized button with a vector icon, optional label, toggle mode, badge
## and long-press tooltip (touch screens have no hover tooltips).
##
##   var b := IconButton.make(&"save", tr("Сохранить"), tr("Сохранить мир"))
##   b.pressed.connect(_on_save)
##   var t := IconButton.make(&"grid", "", tr("Сетка"), &"FlatButton")
##   t.toggle_mode = true                       # → toggled(on)
##   b.badge = "3"                               # small count bubble
##   var tab := IconButton.make(&"leaf", tr("Флора")); tab.vertical = true
##
## Signals (besides Button's pressed/toggled):
##   long_pressed — held ≥ long_press_time without moving; shows `tooltip_text`
##                  as a bubble and suppresses the click.

signal long_pressed

## Icon id (Icons.names()); empty = text-only button.
@export var icon_name: StringName = &"":
	set(v):
		icon_name = v
		_update_icon()
## Icon above the label (tab / tile style) instead of left of it.
@export var vertical: bool = false:
	set(v):
		vertical = v
		_update_layout()
## Short badge text drawn at the top-right corner ("" = none), e.g. "3" or "!".
@export var badge: String = "":
	set(v):
		badge = v
		queue_redraw()
## Badge colour token (UITheme.TYPE colour name).
@export var badge_role: StringName = &"highlight"
## Icon size relative to the theme icon size.
@export var icon_scale: float = 1.0:
	set(v):
		icon_scale = v
		_update_icon()
@export var long_press_time: float = 0.5

const MOVE_CANCEL_PX := 18.0

var _tex: IconTexture
var _hold := -1.0
var _press_pos := Vector2.ZERO
var _long_fired := false
var _bubble: Control


static func make(icon_id: StringName, label: String = "", tooltip: String = "", variation: StringName = &"") -> IconButton:
	var b := IconButton.new()
	b.icon_name = icon_id
	b.text = label
	b.tooltip_text = tooltip
	if variation != &"":
		b.theme_type_variation = variation
	return b


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	expand_icon = false
	set_process(false)


func _ready() -> void:
	_update_icon()
	_update_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_update_icon()
		_update_layout()
	elif what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_VISIBILITY_CHANGED:
		_hide_bubble()


func _update_icon() -> void:
	if icon_name == &"":
		icon = null
		return
	if _tex == null:
		_tex = IconTexture.new()
	_tex.icon = icon_name
	_tex.size_px = int(round(UITheme.k(self, &"icon") * icon_scale))
	if icon != _tex:
		icon = _tex


func _update_layout() -> void:
	var t := UITheme.k(self, &"touch")
	if vertical:
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		add_theme_font_size_override("font_size", UITheme.font_size(self, &"small"))
		custom_minimum_size = Vector2(t * 1.3, t * 1.35) if text != "" else Vector2(t, t)
	else:
		icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		remove_theme_font_size_override("font_size")
		custom_minimum_size = Vector2(t, t)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and not disabled:
			_hold = 0.0
			_press_pos = mb.position
			_long_fired = false
			set_process(true)
		elif not mb.pressed:
			_hold = -1.0
			set_process(false)
			if _long_fired:
				_long_fired = false
				accept_event()
				# Reset BaseButton's internal press state without emitting `pressed`.
				var was := disabled
				disabled = true
				disabled = was
				_hide_bubble_later()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _hold >= 0.0 and mm.position.distance_to(_press_pos) > MOVE_CANCEL_PX * UITheme.scale_of(self):
		_hold = -1.0
		set_process(false)


func _process(delta: float) -> void:
	if _hold < 0.0:
		set_process(false)
		return
	_hold += delta
	if _hold >= long_press_time:
		_hold = -1.0
		set_process(false)
		_long_fired = true
		if tooltip_text != "":
			_show_bubble(tooltip_text)
		long_pressed.emit()


func _draw() -> void:
	if badge == "":
		return
	var font := UITheme.bold_font(self)
	var fsz := UITheme.font_size(self, &"tiny")
	var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var h := float(fsz) * 1.45
	var w := maxf(h, tw + h * 0.6)
	var r := Rect2(Vector2(size.x - w * 0.8, -h * 0.25), Vector2(w, h))
	var bg := UITheme.color(self, badge_role)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(h * 0.5))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	var fg := UITheme.color(self, &"accent_text")
	draw_string(font, Vector2(r.position.x + (w - tw) * 0.5, r.position.y + h * 0.5 + font.get_ascent(fsz) * 0.36),
		badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, fg)


# --- Long-press bubble ---------------------------------------------------------

func _show_bubble(text_value: String) -> void:
	_hide_bubble()
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.top_level = true
	panel.z_index = 100
	var l := Label.new()
	l.text = text_value
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = minf(320.0 * UITheme.scale_of(self), get_viewport_rect().size.x - 32.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	add_child(panel, false, Node.INTERNAL_MODE_BACK)
	_bubble = panel
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.size = panel.get_combined_minimum_size()
	var vp := get_viewport_rect().size
	var g := get_global_rect()
	var pos := Vector2(g.get_center().x - panel.size.x * 0.5, g.position.y - panel.size.y - 10.0)
	if pos.y < 8.0:
		pos.y = g.end.y + 10.0
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - panel.size.x - 8.0))
	panel.global_position = pos


func _hide_bubble_later() -> void:
	var b := _bubble
	if b == null:
		return
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(b) and b == _bubble:
		_hide_bubble()


func _hide_bubble() -> void:
	if is_instance_valid(_bubble):
		_bubble.queue_free()
	_bubble = null
