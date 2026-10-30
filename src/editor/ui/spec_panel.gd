class_name SpecPanel
extends RefCounted
## Turns PanelSpec items (data) into touch widgets bound to a BodyPart and to
## the EditorDocument. Continuous changes go through `doc.live_edit` (cheap
## rebuild, low-LOD mesh); the final value is committed as one undo step.
##
##   var sp := SpecPanel.new(ctx, part.id)
##   sp.add_items(box, PanelSpec.params_for(part.kind))
##   ...
##   sp.refresh()      # after a commit: re-read values into the widgets

var ctx: EditorContext
var part_id: int
var _refreshers: Array[Callable] = []


func _init(c: EditorContext, pid: int) -> void:
	ctx = c
	part_id = pid


func part() -> BodyPart:
	return ctx.doc.plan().get_part(part_id)


func refresh() -> void:
	for r in _refreshers:
		r.call()


## Breaks the reference cycle (refresher lambdas capture `self`). Call when the
## widgets built by this panel are discarded.
func dispose() -> void:
	_refreshers.clear()


## Adds a widget per item. `seg` is the segment index for &"segment" items.
func add_items(box: Container, items: Array, seg: int = 0) -> void:
	for it in items:
		var w := _make_widget(it, seg)
		if w != null:
			box.add_child(w)


# --- Reading / writing ---------------------------------------------------------------------

static func read_value(p: BodyPart, item: Dictionary, seg: int) -> Variant:
	var key := str(item["key"])
	match item["target"]:
		&"param":
			return p.get_param(key)
		&"chain":
			match key:
				"segment_count": return p.segments.size()
				"length": return EditorCommands.chain_length(p)
				"thickness": return EditorCommands.chain_thickness(p)
				"taper": return EditorCommands.chain_taper(p)
				"bend": return EditorCommands.chain_bend(p)
				"mobility": return EditorCommands.chain_mobility(p)
				"stiffness": return EditorCommands.chain_stiffness(p)
		&"segment":
			if p.segments.is_empty():
				return 0.0
			return p.segments[clampi(seg, 0, p.segments.size() - 1)].get(key)
		&"part":
			if key == "function" or key == "kind":
				return str(p.get(key))
			return p.get(key)
	return null


static func write_value(p: BodyPart, item: Dictionary, seg: int, value: Variant) -> void:
	if p == null:
		return
	var key := str(item["key"])
	match item["target"]:
		&"param":
			p.set_param(key, value)
		&"chain":
			match key:
				"segment_count": EditorCommands.set_segment_count(p, int(value))
				"length": EditorCommands.set_chain_length(p, float(value))
				"thickness": EditorCommands.set_chain_thickness(p, float(value))
				"taper": EditorCommands.set_chain_taper(p, float(value))
				"bend": EditorCommands.set_chain_bend(p, float(value))
				"mobility": EditorCommands.set_chain_mobility(p, float(value))
				"stiffness": EditorCommands.set_chain_stiffness(p, float(value))
		&"segment":
			if not p.segments.is_empty():
				var s: BodySegment = p.segments[clampi(seg, 0, p.segments.size() - 1)]
				s.set(key, float(value))
		&"part":
			match key:
				"function":
					p.function = StringName(str(value))
				"symmetry":
					EditorCommands.set_symmetry(p, int(value))
				"repeat_count", "covering":
					p.set(key, int(value))
				"label":
					p.label = str(value)
				"locked":
					p.locked = bool(value)
				"attach_angle":
					p.attach_angle = wrapf(float(value), 0.0, 360.0)
				_:
					p.set(key, float(value))


## Undo-history tag of an item (feeds tutorial events).
static func tag_of(item: Dictionary) -> StringName:
	match item["target"]:
		&"chain", &"segment":
			return &"shape"
		&"param":
			return &"params"
	var key := str(item["key"])
	if key in ["attach_t", "attach_angle", "attach_depth", "yaw", "pitch", "roll", "symmetry", "repeat_count", "repeat_span", "repeat_yaw"]:
		return &"attach"
	if key == "covering":
		return &"covering"
	return &"shape"


func _edit(item: Dictionary, seg: int, value: Variant, final: bool) -> void:
	var pid := part_id
	var label := str(item.get("label", ""))
	if final:
		ctx.doc.live_edit(func(g: Genome) -> void: SpecPanel.write_value(g.body_plan.get_part(pid), item, seg, value))
		ctx.doc.commit(label, tag_of(item))
	else:
		ctx.doc.live_edit(func(g: Genome) -> void: SpecPanel.write_value(g.body_plan.get_part(pid), item, seg, value))


# --- Widgets --------------------------------------------------------------------------------------

func _make_widget(item: Dictionary, seg: int) -> Control:
	var p := part()
	if p == null:
		return null
	var type := str(item.get("type", "float"))
	var label := str(item.get("label", item["key"]))
	var cur: Variant = read_value(p, item, seg)
	match type:
		"float", "int":
			return _slider(item, seg, label, cur, type == "int")
		"bool":
			var tr_ := ToggleRow.make(label, str(item.get("hint", "")), &"", bool(cur))
			tr_.toggled.connect(func(on: bool) -> void: _edit(item, seg, on, true))
			_refreshers.append(func() -> void:
				var q := part()
				if q != null:
					tr_.button_pressed = bool(read_value(q, item, seg)))
			return tr_
		"enum":
			return _enum(item, seg, label, cur)
		"color":
			var cf := EditorUI.color_field(label, cur as Color if cur is Color else Color.WHITE,
				func(c: Color) -> void: _edit(item, seg, c, false),
				func(c: Color) -> void: _edit(item, seg, c, true))
			return cf
		"text":
			var box := VBoxContainer.new()
			var cap := EditorUI.caption(label)
			var le := LineEdit.new()
			le.text = str(cur)
			le.placeholder_text = PartSchema.label(p.kind)
			le.max_length = 40
			le.text_submitted.connect(func(t: String) -> void:
				_edit(item, seg, t, true)
				le.release_focus())
			le.focus_exited.connect(func() -> void:
				var q := part()
				if q != null and q.label != le.text:
					_edit(item, seg, le.text, true))
			box.add_child(cap)
			box.add_child(le)
			return box
		"symmetry":
			return _symmetry(item, seg)
	return null


func _slider(item: Dictionary, seg: int, label: String, cur: Variant, is_int: bool) -> Control:
	var fac := float(item.get("factor", 1.0))
	var mn := float(item.get("min", 0.0))
	var mx := float(item.get("max", 1.0))
	var stp := float(item.get("step", 1.0 if is_int else 0.01))
	var s := ParamSlider.make(label, mn, mx, stp, float(cur), str(item.get("unit", "")))
	s.display_factor = fac
	s.exponential = bool(item.get("exp", false)) and mn > 0.0
	if is_int:
		s.decimals = 0
	s.value_changed.connect(func(v: float) -> void: _edit(item, seg, int(round(v)) if is_int else v, false))
	s.value_committed.connect(func(v: float) -> void: _edit(item, seg, int(round(v)) if is_int else v, true))
	var s_ref := s
	_refreshers.append(func() -> void:
		var q := part()
		if q != null and is_instance_valid(s_ref):
			var v: Variant = read_value(q, item, seg)
			if v != null:
				# Widen the range when the stored value lies outside (old saves).
				s_ref.set_value(float(v)))
	if item.has("hint"):
		s.tooltip_text = str(item["hint"])
		if ctx.hints:
			var v := VBoxContainer.new()
			v.add_child(s)
			var h := EditorUI.caption(str(item["hint"]))
			h.add_theme_font_size_override("font_size", 14)
			v.add_child(h)
			return v
	return s


func _enum(item: Dictionary, seg: int, label: String, cur: Variant) -> Control:
	var labels: Dictionary = item.get("labels", {})
	var items := []
	for o in item.get("options", []):
		var txt: String = str(labels.get(StringName(str(o)), labels.get(str(o), PartSchema.enum_label(str(o)))))
		items.append({"id": str(o), "label": txt})
	var chars := 0
	for it in items:
		chars += str(it["label"]).length()
	var p := EnumPicker.make(label, items, str(cur), EnumPicker.Mode.SEGMENTED if items.size() <= 3 and chars <= 20 else EnumPicker.Mode.SHEET)
	p.selected.connect(func(id: Variant) -> void: _edit(item, seg, str(id), true))
	_refreshers.append(func() -> void:
		var q := part()
		if q != null and is_instance_valid(p):
			p.selected_id = str(read_value(q, item, seg)))
	return p


func _symmetry(item: Dictionary, seg: int) -> Control:
	var p := part()
	var box := VBoxContainer.new()
	var cur := p.symmetry
	var mode := 0 if cur <= 0 else (1 if cur == 1 else 2)
	var picker := EnumPicker.make(str(item.get("label", "Симметрия")), [
		{"id": 0, "label": TranslationServer.translate("Нет")},
		{"id": 1, "label": TranslationServer.translate("Зеркало")},
		{"id": 2, "label": TranslationServer.translate("Радиально")}], mode, EnumPicker.Mode.SEGMENTED)
	box.add_child(picker)
	var n_item := PanelSpec.item("symmetry", &"part", "int", TranslationServer.translate("Число лучей"), {"min": 3, "max": 12, "step": 1})
	var n_slider := ParamSlider.make(n_item["label"], 3, 12, 1, maxf(3.0, float(cur)))
	n_slider.decimals = 0
	n_slider.visible = mode == 2
	n_slider.value_changed.connect(func(v: float) -> void: _edit(n_item, seg, int(v), false))
	n_slider.value_committed.connect(func(v: float) -> void: _edit(n_item, seg, int(v), true))
	box.add_child(n_slider)
	picker.selected.connect(func(id: Variant) -> void:
		var m := int(id)
		n_slider.visible = m == 2
		var val := 0 if m == 0 else (1 if m == 1 else maxi(3, int(n_slider.value)))
		_edit(item, seg, val, true))
	return box
