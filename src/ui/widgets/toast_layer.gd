class_name ToastLayer
extends Control
## Stack of short notifications at the top of the screen (below the safe
## area, away from thumbs). Listens to `EventBus.notify(text, level)` when
## `listen_bus` is true (UIOverlay hosts one that survives scene changes).
## Levels: &"info", &"success", &"warning", &"error" — each has its own icon
## AND colour stripe (colour-blind safe). Tap a toast to dismiss it; repeated
## identical messages collapse into one with a "×N" counter.
##
##   UIApp.notify(tr("Мир сохранён"), &"success")        # via EventBus
##   toast_layer.show_toast(tr("Нет места"), &"warning")   # direct

const MAX_VISIBLE := 4
const LEVEL_ICONS := {&"info": &"info", &"success": &"check", &"warning": &"warning", &"error": &"error"}
const LEVEL_COLORS := {&"info": &"info", &"success": &"good", &"warning": &"warn", &"error": &"bad"}

@export var listen_bus: bool = true

var _box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func _ready() -> void:
	if listen_bus:
		UIApp.listen(&"notify", _on_notify)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _box != null:
		UITheme.override_const(_box, "separation", UITheme.k(self, &"gap"))
		_layout.call_deferred()
	elif what == NOTIFICATION_RESIZED:
		_layout.call_deferred()


func _on_notify(text: String, level: StringName) -> void:
	show_toast(text, level)


## Shows a toast. duration < 0 → automatic (longer for long text and errors).
func show_toast(text: String, level: StringName = &"info", duration: float = -1.0) -> Control:
	if not LEVEL_ICONS.has(level):
		level = &"info"
	for t in _box.get_children():
		if t.get_meta(&"text", "") == text and t.get_meta(&"level", &"") == level and not t.get_meta(&"dying", false):
			var n: int = int(t.get_meta(&"count", 1)) + 1
			t.set_meta(&"count", n)
			(t.get_meta(&"count_label") as Label).text = "×%d" % n
			(t.get_meta(&"count_label") as Label).visible = true
			t.set_meta(&"until", Time.get_ticks_msec() / 1000.0 + _auto_duration(text, level))
			return t
	if duration < 0.0:
		duration = _auto_duration(text, level)
	var toast := _make_toast(text, level)
	toast.set_meta(&"until", Time.get_ticks_msec() / 1000.0 + duration)
	_box.add_child(toast)
	while _box.get_child_count() > MAX_VISIBLE:
		var old := _box.get_child(0)
		_box.remove_child(old)
		old.queue_free()
	toast.modulate.a = 0.0
	var tw := toast.create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.18)
	_layout.call_deferred()
	set_process(true)
	return toast


func clear() -> void:
	for t in _box.get_children():
		t.queue_free()


func _auto_duration(text: String, level: StringName) -> float:
	var d := 2.4 + 0.045 * text.length()
	if level == &"error":
		d *= 1.6
	elif level == &"warning":
		d *= 1.25
	return clampf(d, 2.4, 9.0)


func _make_toast(text: String, level: StringName) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ToastPanel"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.set_meta(&"text", text)
	p.set_meta(&"level", level)
	var col := UITheme.color(self, LEVEL_COLORS[level])
	var sb := (get_theme_stylebox(&"panel", &"ToastPanel") as StyleBoxFlat)
	if sb != null:
		sb = sb.duplicate()
		sb.border_color = Color(col, 0.9)
		sb.border_width_left = maxi(3, int(4 * UITheme.scale_of(self)))
		p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.override_const(h, "separation", UITheme.k(self, &"gap_large"))
	p.add_child(h)
	var iv := IconView.make(LEVEL_ICONS[level], UITheme.k(self, &"icon"), &"")
	iv.color = col
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(iv)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var cnt := Label.new()
	cnt.theme_type_variation = &"DimLabel"
	cnt.visible = false
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cnt)
	p.set_meta(&"count_label", cnt)
	p.gui_input.connect(func(e: InputEvent) -> void:
		var st := e as InputEventScreenTouch
		if st != null and not st.pressed:
			_dismiss(p))
	return p


func _dismiss(t: Control) -> void:
	if not is_instance_valid(t) or t.get_meta(&"dying", false):
		return
	t.set_meta(&"dying", true)
	var tw := t.create_tween()
	tw.tween_property(t, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		if is_instance_valid(t):
			t.queue_free()
		_layout.call_deferred())


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for t in _box.get_children():
		if now >= float(t.get_meta(&"until", 0.0)):
			_dismiss(t)
	if _box.get_child_count() == 0:
		set_process(false)


func _layout() -> void:
	if not is_inside_tree():
		return
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	var ins := SafeArea.insets_for(self)
	var sc := UITheme.scale_of(self)
	var w := minf(vp.x - ins.x - ins.z - 24.0 * sc, 560.0 * sc)
	_box.size = Vector2(w, 0)
	_box.custom_minimum_size.x = w
	_box.position = Vector2(ins.x + (vp.x - ins.x - ins.z - w) * 0.5, ins.y + 12.0 * sc)
	_box.reset_size()
