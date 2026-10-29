class_name LayoutEditor
extends Control
## Full-screen overlay for customising on-screen controls: drag elements with
## a finger, resize with separate −/+ buttons (no pinch needed), set opacity,
## hide/show, reset one element or the whole mode, then save.
## Works in the displayed (left-handed mirrored) space.
##
##   var ed := LayoutEditor.open_for(layout, &"third_person")     # host: UIOverlay dialogs
##   ed.closed.connect(func(saved): if saved: hud.relayout())
##
## Signals: layout_changed (any edit), closed(saved: bool)

signal layout_changed
signal closed(saved: bool)

const SIZE_STEP := 0.1
const GRID := 8.0

var layout: ControlLayout
var mode: StringName = &"third_person"
## Persist on "Готово" (false: caller saves).
var save_on_done: bool = true

var _selected: StringName = &""
var _ghosts: Dictionary = {}
var _panel: PanelContainer
var _name_label: Label
var _size_label: Label
var _opacity: ParamSlider
var _visible_btn: IconButton
var _panel_top := true
var _backup: Dictionary = {}


static func open_for(l: ControlLayout, m: StringName, host: Node = null) -> LayoutEditor:
	var ed := LayoutEditor.new()
	ed.layout = l
	ed.mode = m
	if host == null:
		host = UIOverlay.dialog_host()
	if host == null:
		var tree := Engine.get_main_loop() as SceneTree
		host = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(ed)
	return ed


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_backup = layout.to_dict()
	_build_panel()
	for id in layout.element_ids(mode):
		var g := Ghost.new()
		g.editor = self
		g.id = id
		add_child(g)
		_ghosts[id] = g
	get_viewport().size_changed.connect(_relayout)
	_relayout.call_deferred()
	var ids := layout.element_ids(mode)
	_select(ids[0] if not ids.is_empty() else &"")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_relayout.call_deferred()
		queue_redraw()


## Safe rect the layout is relative to (same as the HUD uses).
func area() -> Rect2:
	var ins := SafeArea.insets_for(self)
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	return Rect2(Vector2(ins.x, ins.y), vp - Vector2(ins.x + ins.z, ins.y + ins.w))


func ui_scale() -> float:
	return UITheme.scale_of(self)


func _relayout() -> void:
	if not is_inside_tree():
		return
	for id in _ghosts:
		var g: Ghost = _ghosts[id]
		var e := layout.element(mode, id)
		var r := ControlLayout.rect_of(e, area(), ui_scale())
		g.position = r.position
		g.size = r.size
		g.element = e
		g.queue_redraw()
	_place_panel()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UITheme.color(self, &"bg_deep"), 0.55))
	var a := area()
	var step := 48.0 * ui_scale()
	var gc := Color(UITheme.color(self, &"grid"), 0.6)
	var x := a.position.x
	while x <= a.end.x:
		draw_line(Vector2(x, a.position.y), Vector2(x, a.end.y), gc, 1.0)
		x += step
	var y := a.position.y
	while y <= a.end.y:
		draw_line(Vector2(a.position.x, y), Vector2(a.end.x, y), gc, 1.0)
		y += step
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color(UITheme.color(self, &"accent"), 0.5)
	sb.set_border_width_all(maxi(1, int(2 * ui_scale())))
	sb.set_corner_radius_all(int(18 * ui_scale()))
	draw_style_box(sb, a)


# --- Tool panel ----------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"DialogPanel"
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UITheme.k(self, &"gap"))
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	var cap := Label.new()
	cap.theme_type_variation = &"CaptionLabel"
	cap.text = tr("Раскладка: %s") % ControlLayout.mode_label(mode)
	titles.add_child(cap)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"SubheaderLabel"
	titles.add_child(_name_label)
	var move := IconButton.make(&"move", "", tr("Переместить панель"), &"FlatButton")
	move.pressed.connect(func() -> void:
		_panel_top = not _panel_top
		_place_panel())
	head.add_child(move)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.k(self, &"gap"))
	v.add_child(row)
	var minus := RepeatButton.make_repeat(&"minus", tr("Меньше"))
	minus.step.connect(func() -> void: _resize(-SIZE_STEP))
	var plus := RepeatButton.make_repeat(&"plus", tr("Больше"))
	plus.step.connect(func() -> void: _resize(SIZE_STEP))
	_size_label = Label.new()
	_size_label.theme_type_variation = &"ValueLabel"
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_label.custom_minimum_size.x = 84.0 * ui_scale()
	_visible_btn = IconButton.make(&"eye", "", tr("Показывать"), &"FlatButton")
	_visible_btn.toggle_mode = true
	_visible_btn.toggled.connect(_on_visible)
	var reset_el := IconButton.make(&"refresh", tr("Сброс"), tr("Вернуть элемент на место"), &"FlatButton")
	reset_el.pressed.connect(func() -> void:
		layout.reset_element(mode, _selected)
		_changed())
	for c in [minus, _size_label, plus, _visible_btn, reset_el]:
		row.add_child(c)
	_opacity = ParamSlider.make(tr("Прозрачность"), 0.15, 1.0, 0.05, 0.9, "%")
	_opacity.display_factor = 100.0
	_opacity.value_changed.connect(func(val: float) -> void:
		layout.set_element(mode, _selected, {"opacity": val})
		_changed())
	v.add_child(_opacity)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", UITheme.k(self, &"gap"))
	v.add_child(foot)
	var reset_all := IconButton.make(&"trash", tr("Сбросить всё"), "", &"FlatButton")
	reset_all.pressed.connect(_confirm_reset_all)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel := IconButton.make(&"", tr("Отмена"))
	cancel.pressed.connect(func() -> void: _finish(false))
	var done := IconButton.make(&"check", tr("Готово"), "", &"AccentButton")
	done.pressed.connect(func() -> void: _finish(true))
	for c in [reset_all, spacer, cancel, done]:
		foot.add_child(c)


func _confirm_reset_all() -> void:
	var do_reset := func() -> void:
		layout.reset_mode(mode)
		_changed()
	ModalDialog.confirm(self, tr("Сбросить раскладку?"),
		tr("Все элементы режима «%s» вернутся на места по умолчанию.") % ControlLayout.mode_label(mode),
		do_reset, tr("Сбросить"), true)


func _place_panel() -> void:
	if _panel == null:
		return
	var a := area()
	var m := 12.0 * ui_scale()
	var w := minf(a.size.x - m * 2.0, 600.0 * ui_scale())
	_panel.custom_minimum_size.x = w
	_panel.size = Vector2(w, 0)
	_panel.reset_size()
	var h := _panel.size.y
	_panel.position = Vector2(a.position.x + (a.size.x - w) * 0.5, a.position.y + m if _panel_top else a.end.y - h - m)


func _select(id: StringName) -> void:
	_selected = id
	for gid in _ghosts:
		(_ghosts[gid] as Ghost).selected = gid == id
	_refresh_panel()


func _refresh_panel() -> void:
	var e := layout.element(mode, _selected)
	if e.is_empty():
		return
	_name_label.text = tr(str(e.get("label", _selected)))
	_size_label.text = "%d %%" % int(round(float(e["size"]) * 100.0))
	_visible_btn.set_pressed_no_signal(bool(e["visible"]))
	_visible_btn.icon_name = &"eye" if bool(e["visible"]) else &"eye_off"
	_opacity.set_value(float(e["opacity"]))


func _resize(delta: float) -> void:
	var e := layout.element(mode, _selected)
	if e.is_empty():
		return
	layout.set_element(mode, _selected, {"size": snappedf(float(e["size"]) + delta, 0.05)})
	_changed()


func _on_visible(on: bool) -> void:
	layout.set_element(mode, _selected, {"visible": on})
	_changed()


func _changed() -> void:
	_relayout()
	_refresh_panel()
	layout_changed.emit()


## Called by a ghost while/after dragging (centre in local coords).
func _ghost_moved(id: StringName, center: Vector2, final: bool) -> void:
	var g := GRID * ui_scale()
	var c := (center / g).round() * g
	if final:
		layout.place_at(mode, id, c, area(), ui_scale())
		_changed()
	else:
		var gh: Ghost = _ghosts[id]
		gh.position = c - gh.size * 0.5
		gh.position = gh.position.clamp(area().position, area().end - gh.size)


func _finish(saved: bool) -> void:
	if saved:
		if save_on_done:
			layout.save()
	else:
		var restored := ControlLayout.from_dict(_backup)
		layout.schemes = restored.schemes
		layout.active_scheme = restored.active_scheme
	closed.emit(saved)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and ModalDialog.top() == null:
		get_viewport().set_input_as_handled()
		_finish(false)


## Draggable stand-in for one control element (private helper).
class Ghost:
	extends Control
	var editor: LayoutEditor
	var id: StringName
	var element: Dictionary = {}
	var selected: bool = false:
		set(v):
			selected = v
			queue_redraw()
	var _touch := -1
	var _grab := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		var st := event as InputEventScreenTouch
		if st != null:
			if st.pressed and _touch < 0:
				_touch = st.index
				_grab = st.position - size * 0.5
				editor._select(id)
				accept_event()
			elif not st.pressed and st.index == _touch:
				_touch = -1
				editor._ghost_moved(id, position + size * 0.5, true)
				accept_event()
			return
		var sd := event as InputEventScreenDrag
		if sd != null and sd.index == _touch:
			editor._ghost_moved(id, position + sd.position - _grab, false)
			accept_event()

	func _draw() -> void:
		if element.is_empty():
			return
		var sc := UITheme.scale_of(self)
		var vis := bool(element.get("visible", true))
		var a := float(element.get("opacity", 0.9)) * (1.0 if vis else 0.35)
		var accent := UITheme.color(self, &"accent")
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r - 1.0, Color(UITheme.color(self, &"panel"), 0.8 * a), true, -1.0, true)
		draw_arc(c, r - 1.5, 0.0, TAU, 48, accent if selected else Color(UITheme.color(self, &"border_strong"), 0.9),
			(3.0 if selected else 1.5) * sc, true)
		var isz := r * (0.6 if element.get("kind") == &"joystick" else 0.8)
		Icons.draw(self, element.get("icon", &"info"), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)),
			Color(UITheme.color(self, &"text"), maxf(a, 0.5)))
		if not vis:
			Icons.draw(self, &"eye_off", Rect2(Vector2(size.x - 22.0 * sc, 0), Vector2(22, 22) * sc), UITheme.color(self, &"warn"))
