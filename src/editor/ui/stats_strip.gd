class_name StatsStrip
extends PanelContainer
## Compact live read-out over the 3D view: mass, what the body can do
## (walk / swim / fly with speeds), energy cost and the warnings badge.
## Tapping the badge opens the diagnostics tab.

var ctx: EditorContext
var _row: HFlowContainer
var _warn: IconButton


func setup(c: EditorContext) -> void:
	ctx = c
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row = HFlowContainer.new()
	_row.alignment = FlowContainer.ALIGNMENT_CENTER
	UITheme.override_const(_row, "h_separation", 14)
	UITheme.override_const(_row, "v_separation", 2)
	add_child(_row)
	# Live edits are throttled by the editor (see CreatureEditor._process).
	ctx.doc.changed.connect(func(r: StringName) -> void:
		if r != &"live":
			refresh())
	refresh()


static func compute(doc: EditorDocument) -> Dictionary:
	var ph := doc.phenotype
	var st := ph.anatomy.stats
	var lp := ph.locomotion
	var out := {}
	out["mass"] = AnatomyDiagnostics.format_mass(float(st.get("mass", 0.0)))
	out["length"] = float(st.get("length", 0.0))
	out["walk"] = lp.best_land_speed() if (lp.can_walk or lp.can_crawl) else 0.0
	out["swim"] = lp.swim_speed if lp.can_swim else 0.0
	out["fly"] = lp.fly_speed if lp.can_fly else (-1.0 if lp.can_glide else 0.0)
	# kcal per real day at rest.
	out["kcal"] = ph.physiology.bmr_watts * 86400.0 / 4184.0
	out["bmr"] = ph.physiology.bmr_watts
	out["warnings"] = doc.warning_count()
	out["critical"] = doc.critical_count()
	return out


func refresh() -> void:
	if _row == null:
		return
	for ch in _row.get_children():
		_row.remove_child(ch)
		EditorUI.dispose(ch)
	var s := compute(ctx.doc)
	_chip(&"scale", "%s · %s" % [s["mass"], tr("%s м") % UIFormat.number(float(s["length"]), 2)], true)
	_chip(&"paw", tr("%s м/с") % UIFormat.number(float(s["walk"]), 1) if float(s["walk"]) > 0.0 else "—", float(s["walk"]) > 0.0)
	_chip(&"fish", tr("%s м/с") % UIFormat.number(float(s["swim"]), 1) if float(s["swim"]) > 0.0 else "—", float(s["swim"]) > 0.0)
	var fly := float(s["fly"])
	_chip(&"bird", tr("%s м/с") % UIFormat.number(fly, 1) if fly > 0.0 else (tr("план.") if fly < 0.0 else "—"), fly != 0.0)
	_chip(&"thermometer", tr("%s Вт") % UIFormat.number(float(s["bmr"]), 0 if float(s["bmr"]) >= 10.0 else 1), true)
	var w := int(s["warnings"])
	_warn = IconButton.make(&"warning" if w > 0 else &"check", str(w) if w > 0 else "", tr("Диагностика"), &"FlatButton")
	_warn.custom_minimum_size = Vector2(UITheme.k(self, &"touch") * (1.0 if w > 0 else 0.85), UITheme.k(self, &"touch") * 0.8)
	_warn.add_theme_color_override("icon_normal_color", UITheme.status_colors()["bad" if int(s["critical"]) > 0 else ("warn" if w > 0 else "good")])
	_warn.add_theme_color_override("font_color", UITheme.status_colors()["bad" if int(s["critical"]) > 0 else "warn"])
	_warn.pressed.connect(func() -> void: ctx.set_mode(&"diagnostics"))
	_row.add_child(_warn)


func _chip(icon_id: StringName, text: String, on: bool) -> void:
	var h := HBoxContainer.new()
	UITheme.override_const(h, "separation", 4)
	var iv := IconView.make(icon_id, 20.0, &"accent" if on else &"text_faint")
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(iv)
	var l := Label.new()
	l.text = text
	l.modulate = Color.WHITE if on else Color(1, 1, 1, 0.5)
	h.add_child(l)
	_row.add_child(h)
