class_name ListRow
extends PanelContainer
## One finger-sized list entry: [icon] title / subtitle  [★] [actions...].
## Used by SearchList; usable alone for custom lists.
##
## Signals:
##   tapped / double_tapped     — on the row body (not on its buttons)
##   favorite_toggled(on)       — star button
##   action(action_id)          — trailing action buttons

signal tapped
signal double_tapped
signal favorite_toggled(on: bool)
signal action(action_id: StringName)

const TAP_SLOP := 16.0
const DOUBLE_TAP_TIME := 0.35

var item_id: Variant = null
var selected: bool = false:
	set(v):
		selected = v
		_apply_style()

var _title: Label
var _subtitle: Label
var _icon: IconView
var _star: IconButton
var _trail: HBoxContainer
var _press_pos := Vector2(-1, -1)
var _last_tap := -10.0
var _styling := false


static func make(id: Variant, title: String, subtitle: String = "", icon_id: StringName = &"") -> ListRow:
	var r := ListRow.new()
	r.item_id = id
	r.set_texts(title, subtitle)
	r.set_icon(icon_id)
	return r


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_icon = IconView.make(&"info", 28.0, &"accent")
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.visible = false
	h.add_child(_icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.override_const(v, "separation", 0)
	h.add_child(v)
	_title = Label.new()
	_title.theme_type_variation = &"SubheaderLabel"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"DimLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	v.add_child(_subtitle)
	_trail = HBoxContainer.new()
	_trail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_trail)


func set_texts(title: String, subtitle: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""


func set_icon(icon_id: StringName, role: StringName = &"accent") -> void:
	_icon.visible = icon_id != &""
	if icon_id != &"":
		_icon.icon = icon_id
		_icon.color_role = role


## Adds the favourite star toggle.
func enable_favorite(on: bool) -> void:
	if _star == null:
		_star = IconButton.make(&"star", "", TranslationServer.translate("Избранное"), &"FlatButton")
		_star.toggle_mode = true
		_star.toggled.connect(func(v: bool) -> void:
			_update_star()
			favorite_toggled.emit(v))
		_trail.add_child(_star)
	_star.set_pressed_no_signal(on)
	_update_star()


func _update_star() -> void:
	if _star != null:
		_star.icon_name = &"star_filled" if _star.button_pressed else &"star"
		_star.add_theme_color_override("icon_pressed_color", UITheme.color(self, &"highlight"))
		_star.add_theme_color_override("icon_hover_pressed_color", UITheme.color(self, &"highlight"))
		# The filled star is the state; no pressed background needed.
		var plain := _star.get_theme_stylebox(&"normal", &"FlatButton")
		var hover := _star.get_theme_stylebox(&"hover", &"FlatButton")
		if plain != null:
			_star.add_theme_stylebox_override("pressed", plain)
			_star.add_theme_stylebox_override("hover_pressed", hover)


func add_action(action_id: StringName, icon_id: StringName, tooltip: String, variation: StringName = &"FlatButton") -> IconButton:
	var b := IconButton.make(icon_id, "", tooltip, variation)
	b.pressed.connect(func() -> void: action.emit(action_id))
	_trail.add_child(b)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _title != null and not _styling:
		_styling = true
		_apply_style()
		UITheme.override_const(get_child(0) as HBoxContainer, "separation", UITheme.k(self, &"gap_large"))
		custom_minimum_size.y = UITheme.k(self, &"touch") * 1.25
		_update_star()
		_styling = false


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	var sc := UITheme.scale_of(self)
	sb.set_corner_radius_all(int(14 * sc))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.content_margin_left = 14 * sc
	sb.content_margin_right = 8 * sc
	sb.content_margin_top = 8 * sc
	sb.content_margin_bottom = 8 * sc
	sb.set_border_width_all(maxi(1, int(round(sc * (2.0 if selected else 1.0)))))
	if selected:
		sb.bg_color = UITheme.color(self, &"card").lerp(UITheme.color(self, &"accent"), 0.16)
		sb.border_color = UITheme.color(self, &"accent")
	else:
		sb.bg_color = UITheme.color(self, &"card")
		sb.border_color = UITheme.color(self, &"border")
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
	elif _press_pos.x >= 0.0 and mb.position.distance_to(_press_pos) < TAP_SLOP * UITheme.scale_of(self):
		_press_pos = Vector2(-1, -1)
		var now := Time.get_ticks_msec() / 1000.0
		tapped.emit()
		if now - _last_tap < DOUBLE_TAP_TIME:
			double_tapped.emit()
			_last_tap = -10.0
		else:
			_last_tap = now
		accept_event()
