class_name StackedAreaChart
extends ChartBase
## Stacked areas: composition over time (population per species, biomass per
## trophic level). The read-out lists each layer and the total.
## `normalized = true` shows shares (0–100 %).
##
##   var s := StackedAreaChart.new()
##   s.add_series(tr("Олени"), deer); s.add_series(tr("Волки"), wolves)

var normalized: bool = false:
	set(v):
		normalized = v
		y_unit = "%" if v else ""
		queue_redraw()


func _stack_value(si: int, i: int) -> float:
	var vals: PackedFloat32Array = series[si]["values"]
	return maxf(vals[i], 0.0) if i < vals.size() and not series[si]["hidden"] else 0.0


func _total(i: int) -> float:
	var t := 0.0
	for si in series.size():
		t += _stack_value(si, i)
	return t


func _data_range() -> Vector2:
	if normalized:
		return Vector2(0, 100)
	var hi := 0.0
	for i in sample_count():
		hi = maxf(hi, _total(i))
	return Vector2(0, maxf(hi, 1.0))


func _draw_data(plot: Rect2, ymap: Callable) -> void:
	var n := sample_count()
	if n < 2:
		return
	var sc := UITheme.scale_of(self)
	var step := maxi(1, int(ceil(float(n) / maxf(plot.size.x * 0.5, 2.0))))
	var idx: Array[int] = []
	var i := 0
	while i < n:
		idx.append(i)
		i += step
	if idx.back() != n - 1:
		idx.append(n - 1)
	var below := PackedFloat32Array()
	below.resize(idx.size())
	for si in series.size():
		if series[si]["hidden"]:
			continue
		var top_pts := PackedVector2Array()
		var bot_pts := PackedVector2Array()
		var above := PackedFloat32Array()
		above.resize(idx.size())
		for k in idx.size():
			var j := idx[k]
			var v := _stack_value(si, j)
			if normalized:
				var t := _total(j)
				v = v / t * 100.0 if t > 0.0 else 0.0
			above[k] = below[k] + v
			var x := _x_of(j)
			top_pts.append(Vector2(x, ymap.call(above[k])))
			bot_pts.append(Vector2(x, ymap.call(below[k])))
		var col := series_color(si)
		var fill := Color(col, 0.55 if scrub_index < 0 else 0.48)
		_fill_band(top_pts, bot_pts, fill)
		draw_polyline(top_pts, col, maxf(1.0, 1.5 * sc), true)
		below = above


## Fills the band between two polylines quad by quad (robust for any shape).
func _fill_band(top: PackedVector2Array, bot: PackedVector2Array, col: Color) -> void:
	for k in top.size() - 1:
		var q := PackedVector2Array([top[k], top[k + 1], bot[k + 1], bot[k]])
		if absf(q[0].y - q[3].y) < 0.01 and absf(q[1].y - q[2].y) < 0.01:
			continue
		draw_colored_polygon(q, col)


func _readout(i: int) -> Array:
	var rows := []
	var total := _total(i)
	for si in range(series.size() - 1, -1, -1):
		if series[si]["hidden"]:
			continue
		var v := _stack_value(si, i)
		var txt := format_value(v)
		if total > 0.0:
			txt += "  (%s %%)" % UIFormat.number(v / total * 100.0, 0)
		rows.append([str(series[si]["name"]), txt, series_color(si)])
	rows.append([tr("Всего"), format_value(total), UITheme.color(self, &"text_dim")])
	return rows
