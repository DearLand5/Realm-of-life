class_name ChartBase
extends Control
## Shared machinery of LineChart / BarChart / StackedAreaChart: series data,
## nice axis ticks with labels, grid, legend (tap to hide a series), colour-
## blind aware colours from the theme, and touch scrubbing — drag a finger
## across the chart to read exact values (mouse hover on PC).
##
##   chart.title = tr("Численность"); chart.x_label = tr("день"); chart.y_unit = ""
##   chart.x_start = 1; chart.x_step = 1
##   chart.add_series(tr("Олени"), PackedFloat32Array([...]))
##   chart.clear_series()
##
## Signals: scrubbed(index) — index under the finger (-1 when released).

signal scrubbed(index: int)

## Optional title drawn top-left.
var title: String = "":
	set(v):
		title = v
		queue_redraw()
## Axis captions.
var x_label: String = "":
	set(v):
		x_label = v
		queue_redraw()
var y_label: String = "":
	set(v):
		y_label = v
		queue_redraw()
## Unit appended to values in the read-out ("°C", "кг").
var y_unit: String = ""
## x value of sample i = x_start + i * x_step.
var x_start: float = 0.0
var x_step: float = 1.0
## Force the y range (NAN = automatic).
var y_min_fixed: float = NAN
var y_max_fixed: float = NAN
var show_legend: bool = true
## Keep the read-out visible this long after the finger lifts.
var scrub_linger: float = 1.6

## [{name: String, values: PackedFloat32Array, color: Color (alpha 0 = auto), hidden: bool}]
var series: Array = []

var scrub_index: int = -1
var _touch := -1
var _linger := 0.0
var _legend_hits: Array = []  # [[Rect2, series_index]]
var _plot := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(200, 160)
	set_process(false)


func add_series(series_name: String, values: PackedFloat32Array, col: Color = Color(0, 0, 0, 0)) -> void:
	series.append({"name": series_name, "values": values, "color": col, "hidden": false})
	queue_redraw()


func set_series_values(i: int, values: PackedFloat32Array) -> void:
	if i >= 0 and i < series.size():
		series[i]["values"] = values
		queue_redraw()


func clear_series() -> void:
	series.clear()
	scrub_index = -1
	queue_redraw()


func series_color(i: int) -> Color:
	var c: Color = series[i].get("color", Color(0, 0, 0, 0))
	return c if c.a > 0.0 else UITheme.series(self, i)


## Number of x samples (max over series).
func sample_count() -> int:
	var n := 0
	for s in series:
		n = maxi(n, (s["values"] as PackedFloat32Array).size())
	return n


func x_value(i: int) -> float:
	return x_start + float(i) * x_step


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _touch < 0:
		_set_scrub(-1)


# --- Overridables --------------------------------------------------------------------

## Visible y range Vector2(min, max) before nice rounding.
func _data_range() -> Vector2:
	var lo := INF
	var hi := -INF
	for s in series:
		if s["hidden"]:
			continue
		for v in s["values"]:
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if lo == INF:
		return Vector2(0, 1)
	return Vector2(minf(lo, 0.0) if lo >= 0.0 else lo, hi)


## Draws the data into the plot rect with y mapped by `ymap(value) -> y px`.
func _draw_data(_plot_rect: Rect2, _ymap: Callable) -> void:
	pass


## Index under a local x position.
func _index_at(x: float) -> int:
	var n := sample_count()
	if n <= 0 or _plot.size.x <= 0.0:
		return -1
	if n == 1:
		return 0
	return clampi(int(round((x - _plot.position.x) / _plot.size.x * float(n - 1))), 0, n - 1)


## Local x of sample i (centre).
func _x_of(i: int) -> float:
	var n := sample_count()
	if n <= 1:
		return _plot.get_center().x
	return _plot.position.x + _plot.size.x * float(i) / float(n - 1)


## Rows of the read-out: [[label, value_text, color]].
func _readout(i: int) -> Array:
	var rows := []
	for si in series.size():
		var s: Dictionary = series[si]
		var vals: PackedFloat32Array = s["values"]
		if s["hidden"] or i >= vals.size():
			continue
		rows.append([str(s["name"]), format_value(vals[i]), series_color(si)])
	return rows


func x_text(i: int) -> String:
	var t := UIFormat.number(x_value(i))
	return "%s %s" % [x_label, t] if x_label != "" else t


func format_value(v: float) -> String:
	var t := UIFormat.number(v, 0 if absf(v) >= 100.0 else (1 if absf(v) >= 10.0 else 2))
	return t + (" " + y_unit if y_unit != "" else "")


# --- Drawing ---------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var fs := UITheme.font_size(self, &"tiny")
	var sc := UITheme.scale_of(self)
	var pad := 10.0 * sc
	var top := pad
	_legend_hits.clear()
	if title != "":
		draw_string(UITheme.bold_font(self), Vector2(pad, top + font.get_ascent(UITheme.font_size(self, &"small"))), title,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2.0, UITheme.font_size(self, &"small"), UITheme.color(self, &"text"))
		top += font.get_height(UITheme.font_size(self, &"small")) + 4.0 * sc
	if show_legend and series.size() > 1:
		top = _draw_legend(font, fs, pad, top, sc)
	var rng := _nice_range()
	var ticks := _ticks(rng)
	var lw := 0.0
	for tv in ticks:
		lw = maxf(lw, font.get_string_size(UIFormat.number(tv), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var bottom := font.get_height(fs) * (2.0 if x_label != "" else 1.0) + 6.0 * sc
	_plot = Rect2(Vector2(pad + lw + 6.0 * sc, top + 4.0 * sc), Vector2.ZERO)
	_plot.size = Vector2(size.x - _plot.position.x - pad, size.y - _plot.position.y - bottom)
	if _plot.size.x < 10.0 or _plot.size.y < 10.0:
		return
	var grid := UITheme.color(self, &"grid")
	var dim := UITheme.color(self, &"text_faint")
	var ymap := func(v: float) -> float:
		return _plot.end.y - (v - rng.x) / maxf(rng.y - rng.x, 1e-9) * _plot.size.y
	for tv in ticks:
		var y: float = ymap.call(tv)
		draw_line(Vector2(_plot.position.x, y), Vector2(_plot.end.x, y), grid, maxf(1.0, sc))
		var lab := UIFormat.number(tv)
		var w := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(_plot.position.x - 6.0 * sc - w, y + font.get_ascent(fs) * 0.38), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	_draw_x_labels(font, fs, dim, sc)
	if y_label != "":
		draw_string(font, Vector2(_plot.position.x, _plot.position.y - 2.0 * sc), y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	_draw_data(_plot, ymap)
	if scrub_index >= 0 and scrub_index < sample_count():
		_draw_scrub(font, fs, sc, ymap)


func _draw_legend(font: Font, fs: int, pad: float, top: float, sc: float) -> float:
	var x := pad
	var h := font.get_height(fs)
	var sw := 10.0 * sc
	for i in series.size():
		var nm := str(series[i]["name"])
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sw + 14.0 * sc
		if x + w > size.x - pad and x > pad:
			x = pad
			top += h + 4.0 * sc
		var hidden: bool = series[i]["hidden"]
		var c := series_color(i)
		if hidden:
			c.a = 0.3
		draw_rect(Rect2(x, top + (h - sw) * 0.5, sw, sw), c)
		draw_string(font, Vector2(x + sw + 5.0 * sc, top + font.get_ascent(fs)), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UITheme.color(self, &"text_faint" if hidden else &"text_dim"))
		# Generous hit area for fingers.
		_legend_hits.append([Rect2(x - 4.0 * sc, top - 8.0 * sc, w, h + 16.0 * sc), i])
		x += w + 8.0 * sc
	return top + h + 4.0 * sc


func _draw_x_labels(font: Font, fs: int, col: Color, sc: float) -> void:
	var n := sample_count()
	if n == 0:
		return
	var y := _plot.end.y + font.get_ascent(fs) + 4.0 * sc
	var sample_w := font.get_string_size(UIFormat.number(x_value(n - 1)) + "00", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_labels := maxi(2, int(_plot.size.x / maxf(sample_w * 1.6, 1.0)))
	var stride := maxi(1, int(ceil(float(n) / float(max_labels))))
	var i := 0
	while i < n:
		var lab := UIFormat.number(x_value(i))
		var w := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := clampf(_x_of(i) - w * 0.5, _plot.position.x - w * 0.5, size.x - w - 2.0)
		draw_string(font, Vector2(x, y), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		i += stride
	if x_label != "":
		var w2 := font.get_string_size(x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(_plot.end.x - w2, y + font.get_height(fs)), x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_scrub(font: Font, fs: int, sc: float, _ymap: Callable) -> void:
	var x := _x_of(scrub_index)
	draw_line(Vector2(x, _plot.position.y), Vector2(x, _plot.end.y), UITheme.color(self, &"text_dim"), maxf(1.0, 1.5 * sc))
	var rows := _readout(scrub_index)
	var header := x_text(scrub_index)
	var bfs := UITheme.font_size(self, &"small")
	var lh := font.get_height(bfs)
	var w := font.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
	for r in rows:
		w = maxf(w, font.get_string_size("%s  %s" % [r[0], r[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x + 16.0 * sc)
	var pad := 8.0 * sc
	var box := Rect2(Vector2.ZERO, Vector2(w + pad * 2.0, lh * (rows.size() + 1) + pad * 2.0))
	box.position.x = x + 12.0 * sc if x + 12.0 * sc + box.size.x < size.x else x - 12.0 * sc - box.size.x
	box.position.x = clampf(box.position.x, 0.0, maxf(0.0, size.x - box.size.x))
	box.position.y = _plot.position.y
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.color(self, &"panel_strong")
	sb.border_color = UITheme.color(self, &"border_strong")
	sb.set_border_width_all(maxi(1, int(sc)))
	sb.set_corner_radius_all(int(10 * sc))
	draw_style_box(sb, box)
	var y := box.position.y + pad + font.get_ascent(bfs)
	draw_string(UITheme.bold_font(self), Vector2(box.position.x + pad, y), header, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, UITheme.color(self, &"text"))
	for r in rows:
		y += lh
		draw_rect(Rect2(box.position.x + pad, y - lh * 0.45, 8.0 * sc, 8.0 * sc), r[2])
		draw_string(font, Vector2(box.position.x + pad + 14.0 * sc, y), "%s  %s" % [r[0], r[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, UITheme.color(self, &"text"))


# --- Axis maths ---------------------------------------------------------------------------

func _nice_range() -> Vector2:
	var r := _data_range()
	if not is_nan(y_min_fixed):
		r.x = y_min_fixed
	if not is_nan(y_max_fixed):
		r.y = y_max_fixed
	if r.y <= r.x:
		r.y = r.x + 1.0
	var st := nice_step((r.y - r.x) / 4.0)
	return Vector2(floorf(r.x / st) * st if is_nan(y_min_fixed) else r.x, ceilf(r.y / st) * st if is_nan(y_max_fixed) else r.y)


func _ticks(r: Vector2) -> PackedFloat32Array:
	var st := nice_step((r.y - r.x) / 4.0)
	var out := PackedFloat32Array()
	var v := ceilf(r.x / st - 1e-6) * st
	while v <= r.y + st * 1e-6 and out.size() < 12:
		out.append(v)
		v += st
	return out


## 1-2-5 rounding of a raw step.
static func nice_step(raw: float) -> float:
	if raw <= 0.0 or is_nan(raw):
		return 1.0
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	var f := raw / mag
	var nf := 1.0 if f < 1.5 else (2.0 if f < 3.0 else (5.0 if f < 7.0 else 10.0))
	return nf * mag


# --- Input ------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null:
		if st.pressed and _touch < 0:
			if _tap_legend(st.position):
				accept_event()
				return
			_touch = st.index
			_set_scrub(_index_at(st.position.x))
			accept_event()
		elif not st.pressed and st.index == _touch:
			_touch = -1
			_linger = scrub_linger
			set_process(true)
		return
	var sd := event as InputEventScreenDrag
	if sd != null and sd.index == _touch:
		_set_scrub(_index_at(sd.position.x))
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _touch < 0 and mm.button_mask == 0 and _plot.has_point(mm.position):
		_set_scrub(_index_at(mm.position.x))


func _tap_legend(p: Vector2) -> bool:
	for h in _legend_hits:
		if (h[0] as Rect2).has_point(p):
			var i: int = h[1]
			series[i]["hidden"] = not bool(series[i]["hidden"])
			queue_redraw()
			return true
	return false


func _process(delta: float) -> void:
	_linger -= delta
	if _linger <= 0.0:
		set_process(false)
		if _touch < 0:
			_set_scrub(-1)


func _set_scrub(i: int) -> void:
	if i == scrub_index:
		return
	scrub_index = i
	scrubbed.emit(i)
	queue_redraw()
