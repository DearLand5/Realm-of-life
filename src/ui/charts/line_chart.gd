class_name LineChart
extends ChartBase
## Line chart for histories (population, trait means, temperature...).
## Long series are decimated to ~2 points per pixel column (min/max kept, so
## spikes stay visible). Scrubbing shows a dot per series.
##
##   var c := LineChart.new()
##   c.title = tr("Численность"); c.x_label = tr("день")
##   c.add_series(tr("Травоеды"), values)
##   c.fill_first = true          # soft area under the first series

## Soft fill under the first visible series.
var fill_first: bool = true
var line_width: float = 2.5


func _draw_data(plot: Rect2, ymap: Callable) -> void:
	var n := sample_count()
	if n == 0:
		return
	var sc := UITheme.scale_of(self)
	var first := true
	for si in series.size():
		var s: Dictionary = series[si]
		if s["hidden"]:
			continue
		var pts := _points(s["values"], plot, ymap)
		if pts.size() < 2:
			if pts.size() == 1:
				draw_circle(pts[0], 3.0 * sc, series_color(si), true, -1.0, true)
			continue
		var col := series_color(si)
		if first and fill_first:
			var poly := pts.duplicate()
			poly.append(Vector2(pts[pts.size() - 1].x, plot.end.y))
			poly.append(Vector2(pts[0].x, plot.end.y))
			var cols := PackedColorArray()
			for p in poly:
				var t := clampf((p.y - plot.position.y) / maxf(plot.size.y, 1.0), 0.0, 1.0)
				cols.append(Color(col, lerpf(0.32, 0.02, t)))
			if not Geometry2D.triangulate_polygon(poly).is_empty():
				draw_polygon(poly, cols)
		first = false
		draw_polyline(pts, col, maxf(1.0, line_width * sc), true)
	if scrub_index >= 0:
		for si in series.size():
			var vals: PackedFloat32Array = series[si]["values"]
			if series[si]["hidden"] or scrub_index >= vals.size():
				continue
			var p := Vector2(_x_of(scrub_index), ymap.call(vals[scrub_index]))
			draw_circle(p, 6.0 * sc, UITheme.color(self, &"panel_strong"), true, -1.0, true)
			draw_circle(p, 4.0 * sc, series_color(si), true, -1.0, true)


func _points(vals: PackedFloat32Array, plot: Rect2, ymap: Callable) -> PackedVector2Array:
	var n := vals.size()
	var total := sample_count()
	var pts := PackedVector2Array()
	if n == 0:
		return pts
	var buckets := int(maxf(plot.size.x * 0.5, 2.0))
	if n <= buckets * 2:
		for i in n:
			pts.append(Vector2(_x_of(i), ymap.call(vals[i])))
		return pts
	var per := float(n) / float(buckets)
	for b in buckets:
		var i0 := int(b * per)
		var i1 := mini(n, int((b + 1) * per))
		var lo_i := i0
		var hi_i := i0
		for i in range(i0, i1):
			if vals[i] < vals[lo_i]:
				lo_i = i
			if vals[i] > vals[hi_i]:
				hi_i = i
		var a := mini(lo_i, hi_i)
		var c := maxi(lo_i, hi_i)
		pts.append(Vector2(plot.position.x + plot.size.x * float(a) / float(maxi(total - 1, 1)), ymap.call(vals[a])))
		if c != a:
			pts.append(Vector2(plot.position.x + plot.size.x * float(c) / float(maxi(total - 1, 1)), ymap.call(vals[c])))
	return pts
