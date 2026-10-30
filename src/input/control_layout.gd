class_name ControlLayout
extends RefCounted
## Model of on-screen control placement: per-mode profiles (observer,
## first_person, third_person, editor) of element id → {anchor, offset, size,
## opacity, visible}, named custom schemes, left-handed mirroring and
## persistence (key "layout" of SaveSystem's controls file).
##
##   var layout := ControlLayout.load_saved()
##   layout.left_handed = UIApp.setting("left_handed", false)
##   var r := layout.rect_for(&"third_person", &"btn_jump", safe_rect, UITheme.ui_scale())
##   layout.apply(&"third_person", {&"btn_jump": jump_button, ...}, safe_rect, UITheme.ui_scale())
##   layout.new_scheme("Мой"); layout.set_element(...); layout.save()
##   layout.register_element(&"third_person", &"btn_grab", {...})   # extra HUD element
##
## Positions are resolution independent: an element hangs from an anchor point
## of the safe area (corners / edge midpoints / centre) with a pixel offset, so
## it stays reachable in portrait and landscape. Only differences from the
## defaults are stored, so improved defaults reach existing players.

const MODES: Array[StringName] = [&"observer", &"first_person", &"third_person", &"editor"]
const DEFAULT_SCHEME := "Стандарт"
const PROPS := ["anchor", "offset", "size", "opacity", "visible"]
const MIN_SIZE := 0.6
const MAX_SIZE := 1.8

## Mirror x for left-handed play (read when resolving elements).
var left_handed: bool = false
var active_scheme: String = DEFAULT_SCHEME
## scheme name → {mode → {id → overrides}}
var schemes: Dictionary = {DEFAULT_SCHEME: {}}

var _defs: Dictionary = ControlLayoutDefaults.all()


static func mode_label(mode: StringName) -> String:
	return TranslationServer.translate(str(ControlLayoutDefaults.MODE_LABELS.get(mode, mode)))


## Adds (or replaces) the default definition of an element (see ControlLayoutDefaults).
func register_element(mode: StringName, id: StringName, def: Dictionary) -> void:
	if not _defs.has(mode):
		_defs[mode] = {}
	var full := {"kind": &"button", "icon": &"info", "action": &"", "label": "", "base": Vector2(72, 72),
		"anchor": Vector2(1, 1), "offset": Vector2(-60, -60), "size": 1.0, "opacity": 0.9, "visible": true}
	full.merge(def, true)
	_defs[mode][id] = full


func modes() -> Array[StringName]:
	var out: Array[StringName] = []
	for m in _defs:
		out.append(m)
	return out


func element_ids(mode: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _defs.get(mode, {}):
		out.append(id)
	return out


func definition(mode: StringName, id: StringName) -> Dictionary:
	return (_defs.get(mode, {}) as Dictionary).get(id, {})


## Resolved element (definition + scheme overrides), mirrored when left-handed
## (or when `mirrored` is given explicitly: 0 = no, 1 = yes, -1 = follow left_handed).
func element(mode: StringName, id: StringName, mirrored: int = -1) -> Dictionary:
	var def := definition(mode, id)
	if def.is_empty():
		return {}
	var e := def.duplicate()
	var ov := _overrides(mode).get(id, {}) as Dictionary
	for k in ov:
		e[k] = ov[k]
	e["size"] = clampf(float(e["size"]), MIN_SIZE, MAX_SIZE)
	e["opacity"] = clampf(float(e["opacity"]), 0.15, 1.0)
	var mir := left_handed if mirrored < 0 else mirrored == 1
	return mirror(e) if mir else e


static func mirror(e: Dictionary) -> Dictionary:
	var m := e.duplicate()
	var a: Vector2 = e["anchor"]
	var o: Vector2 = e["offset"]
	m["anchor"] = Vector2(1.0 - a.x, a.y)
	m["offset"] = Vector2(-o.x, o.y)
	return m


## Stores properties given in the DISPLAYED space (mirrored if left-handed).
func set_element(mode: StringName, id: StringName, props: Dictionary) -> void:
	if definition(mode, id).is_empty():
		return
	var p := props.duplicate()
	if left_handed:
		if p.has("anchor"):
			p["anchor"] = Vector2(1.0 - (p["anchor"] as Vector2).x, (p["anchor"] as Vector2).y)
		if p.has("offset"):
			p["offset"] = Vector2(-(p["offset"] as Vector2).x, (p["offset"] as Vector2).y)
	var ov := _overrides(mode, true)
	var cur: Dictionary = ov.get(id, {})
	var def := definition(mode, id)
	for k in PROPS:
		if not p.has(k):
			continue
		var v: Variant = p[k]
		if k == "size":
			v = clampf(float(v), MIN_SIZE, MAX_SIZE)
		if _same(v, def[k]):
			cur.erase(k)
		else:
			cur[k] = v
	if cur.is_empty():
		ov.erase(id)
	else:
		ov[id] = cur


static func _same(a: Variant, b: Variant) -> bool:
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b)
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b


func reset_element(mode: StringName, id: StringName) -> void:
	_overrides(mode, true).erase(id)


func reset_mode(mode: StringName) -> void:
	_scheme(true).erase(String(mode))


func reset_scheme() -> void:
	schemes[active_scheme] = {}


## Screen rect of an element inside `area` (the safe rect), clamped to it.
func rect_for(mode: StringName, id: StringName, area: Rect2, ui_scale: float = 1.0) -> Rect2:
	var e := element(mode, id)
	if e.is_empty():
		return Rect2()
	return rect_of(e, area, ui_scale)


static func rect_of(e: Dictionary, area: Rect2, ui_scale: float) -> Rect2:
	var sz: Vector2 = (e["base"] as Vector2) * float(e["size"]) * ui_scale
	sz = sz.min(area.size)
	var c: Vector2 = area.position + area.size * (e["anchor"] as Vector2) + (e["offset"] as Vector2) * ui_scale
	var r := Rect2(c - sz * 0.5, sz)
	r.position = r.position.clamp(area.position, area.end - sz)
	return r


## Positions, sizes and fades the given controls (id → Control); hides hidden ones.
func apply(mode: StringName, controls: Dictionary, area: Rect2, ui_scale: float = 1.0) -> void:
	for id in controls:
		var c := controls[id] as Control
		var e := element(mode, id)
		if c == null or e.is_empty():
			continue
		var r := rect_of(e, area, ui_scale)
		c.position = r.position
		c.size = r.size
		c.modulate.a = float(e["opacity"])
		c.visible = bool(e["visible"])


## Moves an element so its centre is at `center` (displayed space), re-anchoring
## it to the nearest anchor point so it adapts well to other screen shapes.
func place_at(mode: StringName, id: StringName, center: Vector2, area: Rect2, ui_scale: float = 1.0) -> void:
	var n := (center - area.position) / area.size.max(Vector2.ONE)
	var anchor := Vector2(_nearest_third(n.x), _nearest_third(n.y))
	var offset := (center - area.position - area.size * anchor) / maxf(ui_scale, 0.01)
	set_element(mode, id, {"anchor": anchor, "offset": offset.round()})


static func _nearest_third(v: float) -> float:
	return 0.0 if v < 0.33 else (1.0 if v > 0.67 else 0.5)


# --- Schemes ----------------------------------------------------------------------

func scheme_names() -> PackedStringArray:
	var out := PackedStringArray(schemes.keys())
	out.sort()
	return out


## Creates a scheme as a copy of `copy_from` (default: active) and activates it.
func new_scheme(scheme_name: String, copy_from: String = "") -> bool:
	if scheme_name.strip_edges() == "" or schemes.has(scheme_name):
		return false
	var src := copy_from if copy_from != "" else active_scheme
	schemes[scheme_name] = (schemes.get(src, {}) as Dictionary).duplicate(true)
	active_scheme = scheme_name
	return true


func set_active(scheme_name: String) -> void:
	if schemes.has(scheme_name):
		active_scheme = scheme_name


func delete_scheme(scheme_name: String) -> void:
	if scheme_name == DEFAULT_SCHEME:
		schemes[DEFAULT_SCHEME] = {}
		return
	schemes.erase(scheme_name)
	if active_scheme == scheme_name:
		active_scheme = DEFAULT_SCHEME


func rename_scheme(old_name: String, new_name: String) -> bool:
	if old_name == DEFAULT_SCHEME or not schemes.has(old_name) or new_name == "" or schemes.has(new_name):
		return false
	schemes[new_name] = schemes[old_name]
	schemes.erase(old_name)
	if active_scheme == old_name:
		active_scheme = new_name
	return true


func _scheme(create: bool = false) -> Dictionary:
	if not schemes.has(active_scheme):
		if not create:
			return {}
		schemes[active_scheme] = {}
	return schemes[active_scheme]


func _overrides(mode: StringName, create: bool = false) -> Dictionary:
	var s := _scheme(create)
	var key := String(mode)
	if not s.has(key):
		if not create:
			return {}
		s[key] = {}
	return s[key]


# --- Persistence -------------------------------------------------------------------------

## JSON-safe dictionary (Vector2 → [x, y]).
func to_dict() -> Dictionary:
	var out_schemes := {}
	for sn in schemes:
		var modes_d := {}
		for m in schemes[sn]:
			var els := {}
			for id in schemes[sn][m]:
				var ov: Dictionary = schemes[sn][m][id]
				var d := {}
				for k in ov:
					d[k] = Serial.v2(ov[k]) if ov[k] is Vector2 else ov[k]
				els[String(id)] = d
			modes_d[String(m)] = els
		out_schemes[sn] = modes_d
	return {"version": 1, "active": active_scheme, "schemes": out_schemes}


## Tolerant of missing/unknown keys and unknown elements (kept for forward compatibility).
static func from_dict(d: Dictionary) -> ControlLayout:
	var l := ControlLayout.new()
	l.schemes = {DEFAULT_SCHEME: {}}
	var src := Serial.dict(d, "schemes")
	for sn in src:
		var modes_d := {}
		var md: Variant = src[sn]
		if not (md is Dictionary):
			continue
		for m in md:
			var els := {}
			if not (md[m] is Dictionary):
				continue
			for id in md[m]:
				var ov: Variant = md[m][id]
				if not (ov is Dictionary):
					continue
				var e := {}
				for k in ov:
					match str(k):
						"anchor", "offset":
							e[str(k)] = Serial.to_v2(ov[k])
						"size", "opacity":
							e[str(k)] = float(ov[k])
						"visible":
							e[str(k)] = bool(ov[k])
				els[StringName(str(id))] = e
			modes_d[str(m)] = els
		l.schemes[str(sn)] = modes_d
	l.active_scheme = Serial.s(d, "active", DEFAULT_SCHEME)
	if not l.schemes.has(l.active_scheme):
		l.active_scheme = DEFAULT_SCHEME
	return l


func save() -> void:
	var all_controls := SaveSystem.load_controls()
	all_controls["layout"] = to_dict()
	SaveSystem.save_controls(all_controls)


static func load_saved() -> ControlLayout:
	var c := SaveSystem.load_controls()
	var l := from_dict(Serial.dict(c, "layout"))
	l.left_handed = bool(UIApp.setting("left_handed", false))
	return l
