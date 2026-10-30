class_name BarChart
extends ChartBase
## Bar chart for categories (trait distribution, species counts, diet mix).
## One series → one bar per category (coloured by category when
## `color_by_category`); several series → grouped bars.
##
##   var b := BarChart.new()
##   b.categories = PackedStringArray([tr("Травоеды"), tr("Хищники"), tr("Всеядные")])
##   b.add_series(tr("Особи"), PackedFloat32Array([420, 37, 96]))

var categories: PackedStringArray = PackedStringArray():
	set(v):
		categories = v
		queue_redraw()
## Single-series charts: one palette colour per bar.
var color_by_category: bool = true
## Bar width as a fraction of the slot.
var bar_fill: float = 0.72


func _init() -> void:
	super()
	show_legend = true


func sample_count() -> int:
	return maxi(categories.size(), super())


func _x_of(i: int) -> float:
	var n := maxi(sample_count(), 1)
	return _plot.position.x + _plot.size.x * (float(i) + 0.5) / float(n)


func _index_at(x: float) -> int:
	var n := sample_count()
	if n <= 0 or _plot.size.x <= 0.0:
		return -1
	return clampi(int((x - _plot.position.x) / _plot.size.x * float(n)), 0, n - 1)


func x_text(i: int) -> String:
	return categories[i] if i < categories.size() else UIFormat.number(x_value(i))


func _data_range() -> Vector2:
	var r := super()
	return Vector2(minf(r.x, 0.0), r.y)


func _draw_x_labels(font: Font, fs: int, col: Color, sc: float) -> void:
	var n := sample_count()
	if n == 0:
		return
	var slot := _plot.size.x / float(n)
	var y := _plot.end.y + font.get_ascent(fs) + 4.0 * sc
	for i in n:
		var lab := x_text(i)
		var w := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > slot - 4.0 * sc:
			lab = lab.substr(0, maxi(1, int(lab.length() * (slot - 4.0 * sc) / maxf(w, 1.0)) - 1)) + "…"
			w = font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(_x_of(i) - w * 0.5, y), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_data(plot: Rect2, ymap: Callable) -> void:
	var n := sample_count()
	if n == 0:
		return
	var visible_series: Array[int] = []
	for si in series.size():
		if not series[si]["hidden"]:
			visible_series.append(si)
	if visible_series.is_empty():
		return
	var sc := UITheme.scale_of(self)
	var slot := plot.size.x / float(n)
	var group_w := slot * bar_fill
	var bw := group_w / float(visible_series.size())
	var zero_y: float = ymap.call(0.0)
	for i in n:
		for k in visible_series.size():
			var si := visible_series[k]
			var vals: PackedFloat32Array = series[si]["values"]
			if i >= vals.size():
				continue
			var x0 := plot.position.x + slot * float(i) + (slot - group_w) * 0.5 + bw * float(k)
			var y1: float = ymap.call(vals[i])
			var r := Rect2(x0 + 1.0 * sc, minf(y1, zero_y), maxf(bw - 2.0 * sc, 1.0), absf(zero_y - y1))
			var col := UITheme.series(self, i) if (visible_series.size() == 1 and color_by_category) else series_color(si)
			if scrub_index >= 0 and scrub_index != i:
				col = Color(col, 0.45)
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			var rad := int(minf(6.0 * sc, r.size.x * 0.3))
			sb.corner_radius_top_left = rad
			sb.corner_radius_top_right = rad
			sb.anti_aliasing = true
			draw_style_box(sb, r)


func _readout(i: int) -> Array:
	var rows := super(i)
	if rows.size() == 1 and color_by_category:
		rows[0][2] = UITheme.series(self, i)
	return rows
