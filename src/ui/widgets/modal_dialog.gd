class_name ModalDialog
extends Control
## Touch-friendly modal: dimmed backdrop + centred panel with title, scrollable
## body and a button row. Sizes adapt to portrait/landscape (never wider than
## the screen minus margins). Back button / Esc and backdrop taps close it when
## `dismissible`.
##
##   var d := ModalDialog.create(tr("Удалить вид?"), tr("Это действие нельзя отменить."))
##   d.add_button(&"cancel", tr("Отмена"))
##   d.add_button(&"delete", tr("Удалить"), &"DangerButton")
##   d.closed.connect(func(r): if r == &"delete": ...)
##   d.open(self)                     # host: any node; null → UIOverlay / current scene
##
##   ModalDialog.confirm(self, tr("Выйти?"), tr("Несохранённые изменения пропадут."), _quit, tr("Выйти"), true)
##   d.content.add_child(my_form)     # custom content (inside the scroll area)
##
## Signals:
##   button_pressed(id) — any footer button
##   closed(result)     — after closing; result = button id or &"cancel"

signal button_pressed(id: StringName)
signal closed(result: StringName)

enum SizeClass { SMALL, MEDIUM, LARGE, FULL }

const MAX_WIDTH := {SizeClass.SMALL: 460.0, SizeClass.MEDIUM: 620.0, SizeClass.LARGE: 940.0, SizeClass.FULL: 100000.0}

static var _stack: Array[ModalDialog] = []

var title: String = ""
var body_text: String = ""
var icon_name: StringName = &""
var size_class: SizeClass = SizeClass.MEDIUM
## Backdrop tap / back button / Esc close the dialog with result &"cancel".
var dismissible: bool = true
## Show the (×) button in the header.
var show_close: bool = true
## Stack footer buttons vertically on narrow screens.
var stack_buttons_when_narrow: bool = true
## Use the full available height and let `content` children expand vertically
## (for dialogs whose content scrolls by itself, e.g. a SearchList).
var expand_content: bool = false

## Custom content goes here (VBox inside the scroll area, below the body text).
var content: VBoxContainer
var footer: BoxContainer

var _scrim: ColorRect
var _margin: MarginContainer
var _center: CenterContainer
var _panel: PanelContainer
var _max_h := 400.0
var _fill_height := false
var _scroll: ScrollContainer
var _title_label: Label
var _body_label: Label
var _buttons: Array[Button] = []
var _closing := false


static func create(title_text: String, body: String = "", icon_id: StringName = &"", sz: SizeClass = SizeClass.MEDIUM) -> ModalDialog:
	var d := ModalDialog.new()
	d.title = title_text
	d.body_text = body
	d.icon_name = icon_id
	d.size_class = sz
	return d


## Yes/no dialog; calls `on_confirm` when confirmed.
static func confirm(host: Node, title_text: String, body: String, on_confirm: Callable,
		confirm_text: String = "", danger: bool = false) -> ModalDialog:
	var d := create(title_text, body, &"warning" if danger else &"help", SizeClass.SMALL)
	d.add_button(&"cancel", TranslationServer.translate("Отмена"))
	d.add_button(&"ok", confirm_text if confirm_text != "" else TranslationServer.translate("Да"),
		&"DangerButton" if danger else &"AccentButton")
	d.closed.connect(func(r: StringName) -> void:
		if r == &"ok" and on_confirm.is_valid():
			on_confirm.call())
	return d.open(host)


## Message with a single OK button.
static func info(host: Node, title_text: String, body: String, icon_id: StringName = &"info") -> ModalDialog:
	var d := create(title_text, body, icon_id, SizeClass.SMALL)
	d.add_button(&"ok", TranslationServer.translate("Понятно"), &"AccentButton")
	return d.open(host)


## The topmost open dialog, or null.
static func top() -> ModalDialog:
	while not _stack.is_empty() and not is_instance_valid(_stack.back()):
		_stack.pop_back()
	return _stack.back() if not _stack.is_empty() else null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"DialogPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)
	_center.add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	var header := HBoxContainer.new()
	header.name = "Header"
	v.add_child(header)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeaderLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title_label)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(inner)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.theme_type_variation = &"DimLabel"
	inner.add_child(_body_label)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(content)
	inner.minimum_size_changed.connect(func() -> void: _update_scroll_height.call_deferred())
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(footer)


## Adds a footer button. `closes` = close the dialog with this id when pressed.
func add_button(id: StringName, text: String, variation: StringName = &"", icon_id: StringName = &"", closes: bool = true) -> Button:
	var b := IconButton.make(icon_id, text, "", variation)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.set_meta(&"dialog_id", id)
	b.pressed.connect(func() -> void:
		button_pressed.emit(id)
		if closes:
			close(id))
	footer.add_child(b)
	_buttons.append(b)
	return b


func set_title(t: String) -> void:
	title = t
	if _title_label != null:
		_title_label.text = t


## Adds the dialog to `host` (null → UIOverlay dialog layer or the current scene).
func open(host: Node = null) -> ModalDialog:
	if host == null:
		host = UIOverlay.dialog_host()
	if host == null:
		var tree := Engine.get_main_loop() as SceneTree
		host = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(self)
	return self


func close(result: StringName = &"cancel") -> void:
	if _closing:
		return
	_closing = true
	_stack.erase(self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_property(_panel, "scale", Vector2(0.97, 0.97), 0.12)
	await tw.finished
	closed.emit(result)
	queue_free()


func _ready() -> void:
	_stack.append(self)
	_title_label.text = title
	_body_label.text = body_text
	_body_label.visible = body_text != ""
	var header := _title_label.get_parent()
	if icon_name != &"":
		var iv := IconView.make(icon_name, 28.0, &"accent")
		header.add_child(iv)
		header.move_child(iv, 0)
	if show_close and dismissible:
		var x := IconButton.make(&"close", "", TranslationServer.translate("Закрыть"), &"FlatButton")
		x.pressed.connect(func() -> void: close(&"cancel"))
		header.add_child(x)
	_apply_theme_bits()
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()
	modulate.a = 0.0
	_panel.scale = Vector2(0.97, 0.97)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not _buttons.is_empty():
		_buttons.back().grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _scrim != null:
		_apply_theme_bits()
		_layout.call_deferred()
	elif what == NOTIFICATION_RESIZED:
		_layout.call_deferred()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and dismissible and top() == self:
		close(&"cancel")


func _apply_theme_bits() -> void:
	_scrim.color = UITheme.color(self, &"scrim")
	var gap := UITheme.k(self, &"gap_large")
	UITheme.override_const(_panel.get_child(0) as VBoxContainer, "separation", gap)
	UITheme.override_const(content, "separation", gap)
	UITheme.override_const(footer, "separation", UITheme.k(self, &"gap"))


func _layout() -> void:
	if not is_inside_tree():
		return
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	var insets := SafeArea.insets_for(self)
	var sc := UITheme.scale_of(self)
	var margin := 16.0 * sc
	UITheme.override_const(_margin, "margin_left", int(insets.x + margin))
	UITheme.override_const(_margin, "margin_top", int(insets.y + margin))
	UITheme.override_const(_margin, "margin_right", int(insets.z + margin))
	UITheme.override_const(_margin, "margin_bottom", int(insets.w + margin))
	var avail := vp - Vector2(insets.x + insets.z, insets.y + insets.w) - Vector2.ONE * margin * 2.0
	var portrait := vp.y > vp.x
	var fill := size_class == SizeClass.FULL or (portrait and size_class == SizeClass.LARGE)
	var max_w: float = MAX_WIDTH[size_class] * sc
	var w := avail.x if fill else minf(avail.x, max_w)
	if stack_buttons_when_narrow:
		_set_footer_vertical(w < 420.0 * sc and footer.get_child_count() > 1)
	_panel.custom_minimum_size.x = w
	_max_h = avail.y if not (expand_content and not fill) else minf(avail.y, 640.0 * sc)
	_fill_height = fill or expand_content
	var inner := _scroll.get_child(0) as Control
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand_content else Control.SIZE_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand_content else Control.SIZE_FILL
	_update_scroll_height()


## Scroll area = content height, capped so the dialog fits the screen.
func _update_scroll_height() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var inner := _scroll.get_child(0) as Control
	var chrome := _panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var room := maxf(_max_h - chrome, 80.0)
	var want := inner.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = room if _fill_height else minf(want, room)


func _set_footer_vertical(v: bool) -> void:
	if (footer is VBoxContainer) == v:
		return
	var nf: BoxContainer = VBoxContainer.new() if v else HBoxContainer.new()
	nf.alignment = BoxContainer.ALIGNMENT_END
	var parent := footer.get_parent()
	var idx := footer.get_index()
	var kids := footer.get_children()
	if v:
		kids.reverse()
	for k in kids:
		footer.remove_child(k)
		nf.add_child(k)
		(k as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if v else Control.SIZE_SHRINK_END
	parent.remove_child(footer)
	footer.queue_free()
	parent.add_child(nf)
	parent.move_child(nf, idx)
	footer = nf
	UITheme.override_const(footer, "separation", UITheme.k(self, &"gap"))


func _unhandled_input(event: InputEvent) -> void:
	if top() != self:
		return
	if event.is_action_pressed(&"ui_cancel") and dismissible:
		get_viewport().set_input_as_handled()
		close(&"cancel")


func _on_scrim_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null and not st.pressed and dismissible and top() == self:
		close(&"cancel")
