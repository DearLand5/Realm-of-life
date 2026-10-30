extends Control
## Genealogical tree of species: x = time of origin (game days), y = lineage
## order. Extinct species are greyed with a cross. Tap a node to select it.

signal species_tapped(id: int)

var data: Dictionary = {}
var _hits: Array = []   # [[Rect2, id]]


func set_data(d: Dictionary) -> void:
	data = d
	var n: int = (d.get("nodes", []) as Array).size()
	custom_minimum_size.y = clampf(40.0 + 34.0 * float(n), 120.0, 520.0)
	queue_redraw()


func _draw() -> void:
	_hits.clear()
	var nodes: Array = data.get("nodes", [])
	if nodes.is_empty():
		return
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	var max_day := 1.0
	var max_order := 1.0
	for nd in nodes:
		max_day = maxf(max_day, float(nd.get("created_day", 0.0)))
		max_day = maxf(max_day, float(nd.get("extinct_day", 0.0)))
		max_order = maxf(max_order, float(nd.get("order", 0)))
	var pad := Vector2(16, 18)
	var w := maxf(10.0, size.x - pad.x * 2.0 - 150.0)
	var h := maxf(10.0, size.y - pad.y * 2.0)
	var pos := {}
	for nd in nodes:
		var x := pad.x + w * float(nd.get("created_day", 0.0)) / max_day
		var y := pad.y + h * float(nd.get("order", 0)) / maxf(1.0, max_order)
		pos[int(nd["id"])] = Vector2(x, y)
	var line_col := Color(0.6, 0.7, 0.7, 0.7)
	for e in data.get("edges", []):
		var a: Vector2 = pos.get(int(e["from"]), Vector2.ZERO)
		var b: Vector2 = pos.get(int(e["to"]), Vector2.ZERO)
		draw_polyline(PackedVector2Array([a, Vector2(b.x, a.y), b]), line_col, 2.0)
	for nd in nodes:
		var p: Vector2 = pos[int(nd["id"])]
		var raw = nd.get("color")
		var col: Color = raw if raw is Color else Serial.to_color(raw, Color.WHITE)
		var extinct := bool(nd.get("extinct", false))
		if extinct:
			col = col.darkened(0.6)
			var ex := pad.x + w * float(nd.get("extinct_day", 0.0)) / max_day
			draw_line(p, Vector2(ex, p.y), col, 2.0)
			draw_line(Vector2(ex - 5, p.y - 5), Vector2(ex + 5, p.y + 5), col, 2.0)
			draw_line(Vector2(ex - 5, p.y + 5), Vector2(ex + 5, p.y - 5), col, 2.0)
		else:
			draw_line(p, Vector2(pad.x + w, p.y), col.lerp(Color.WHITE, 0.2), 3.0)
		draw_circle(p, 7.0, col)
		var label := "%s (%d)" % [str(nd.get("name", "?")), int(float(nd.get("count", 0.0)))]
		draw_string(font, Vector2(pad.x + w + 10.0, p.y + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, 145.0, fs, col.lightened(0.2))
		_hits.append([Rect2(p - Vector2(14, 14), Vector2(28 + w, 28)), int(nd["id"])])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var pt: Vector2 = (event as InputEventScreenTouch).position
		for hit in _hits:
			if (hit[0] as Rect2).has_point(pt):
				species_tapped.emit(int(hit[1]))
				accept_event()
				return
