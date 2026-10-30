class_name MenuBackground
extends Control
## Light animated backdrop for the main menu: deep teal gradient with soft
## glows, slowly drifting translucent "cells" (wobbling organic blobs with
## nuclei) and rising spores. Pure 2D, redrawn at ≤ 30 fps (≤ 15 fps with
## battery saver) and paused when hidden.

const BLOBS := 7
const SPORES := 46

var time_scale: float = 1.0
## Draw the slowly turning planet (landscape only).
var show_planet: bool = true

var _t := 0.0
var _acc := 0.0
var _blobs: Array = []
var _spores: Array = []
var _glow: GradientTexture2D
var _vignette: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := Rng.new(20261029)
	for i in BLOBS:
		_blobs.append({
			"p": Vector2(rng.randf(), rng.randf()), "v": Vector2(rng.range_f(-1, 1), rng.range_f(-1, 1)).normalized() * rng.range_f(0.004, 0.012),
			"r": rng.range_f(0.06, 0.16), "ph": rng.range_f(0, TAU), "spin": rng.range_f(-0.15, 0.15),
			"hue": rng.range_i(0, 2), "nuc": rng.chance(0.75),
		})
	for i in SPORES:
		_spores.append({"p": Vector2(rng.randf(), rng.randf()), "s": rng.range_f(0.006, 0.02), "r": rng.range_f(1.0, 2.6),
			"ph": rng.range_f(0, TAU), "a": rng.range_f(0.15, 0.55)})
	_glow = _radial([Color(0.37, 0.84, 0.66, 0.16), Color(0.37, 0.84, 0.66, 0.0)])
	_vignette = _radial([Color(0, 0, 0, 0.0), Color(0, 0.01, 0.01, 0.55)], 0.35)


static func _radial(cols: Array, start: float = 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[1])
	if start > 0.0:
		g.set_offset(0, start)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## Advances the animation by `dt` seconds (also used by previews).
func advance(dt: float) -> void:
	_t += dt * time_scale
	for b in _blobs:
		var p: Vector2 = b["p"] + b["v"] * dt * time_scale
		var r: float = b["r"]
		if p.x < -r or p.x > 1.0 + r:
			b["v"].x = -b["v"].x
		if p.y < -r or p.y > 1.0 + r:
			b["v"].y = -b["v"].y
		b["p"] = p
	for s in _spores:
		var p2: Vector2 = s["p"]
		p2.y -= float(s["s"]) * dt * time_scale
		p2.x += sin(_t * 0.6 + float(s["ph"])) * 0.0006
		if p2.y < -0.02:
			p2 = Vector2(fposmod(p2.x + 0.37, 1.0), 1.02)
		s["p"] = p2
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_acc += delta
	var fps := 15.0 if bool(UIApp.setting("battery_saver", false)) else 30.0
	if _acc >= 1.0 / fps:
		advance(_acc)
		_acc = 0.0


func _draw() -> void:
	var sz := size
	var top := UITheme.color(self, &"bg")
	var bottom := UITheme.color(self, &"bg_deep")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]),
		PackedColorArray([top.lightened(0.04), top, bottom, bottom.lightened(0.02)]))
	var m := maxf(sz.x, sz.y)
	draw_texture_rect(_glow, Rect2(Vector2(sz.x * 0.72, sz.y * 0.18) - Vector2(m, m) * 0.45, Vector2(m, m) * 0.9), false)
	draw_texture_rect(_glow, Rect2(Vector2(sz.x * 0.1, sz.y * 0.95) - Vector2(m, m) * 0.35, Vector2(m, m) * 0.7), false, Color(0.6, 0.8, 1.0, 0.7))
	var accent := UITheme.color(self, &"accent")
	var tints := [accent, Color("#58b7f0"), Color("#7fe0d0")]
	for b in _blobs:
		_draw_blob(b, sz, m, tints[int(b["hue"])])
	if show_planet and sz.x > sz.y * 1.15:
		_draw_planet(Vector2(sz.x * 0.69, sz.y * 0.4), sz.y * 0.2, accent)
	for s in _spores:
		var p: Vector2 = (s["p"] as Vector2) * sz
		var a: float = float(s["a"]) * (0.6 + 0.4 * sin(_t * 1.3 + float(s["ph"])))
		draw_circle(p, float(s["r"]), Color(0.85, 1.0, 0.92, a), true, -1.0, true)
	draw_texture_rect(_vignette, Rect2(Vector2(sz.x * 0.5, sz.y * 0.5) - Vector2(m, m) * 0.75, Vector2(m, m) * 1.5), false)


func _draw_blob(b: Dictionary, sz: Vector2, m: float, tint: Color) -> void:
	var c: Vector2 = (b["p"] as Vector2) * sz
	var r: float = float(b["r"]) * m
	var ph: float = b["ph"]
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var a := TAU * float(i) / float(n) + _t * float(b["spin"])
		var w := 1.0 + 0.06 * sin(a * 2.0 + _t * 0.7 + ph) + 0.03 * sin(a * 3.0 - _t * 0.5 + ph * 2.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * w)
	draw_colored_polygon(pts, Color(tint, 0.035))
	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, Color(tint, 0.10), maxf(1.0, r * 0.01), true)
	if b["nuc"]:
		var nc := c + Vector2(cos(ph + _t * 0.2), sin(ph + _t * 0.2)) * r * 0.25
		draw_circle(nc, r * 0.2, Color(tint, 0.05), true, -1.0, true)
		draw_arc(nc, r * 0.2, 0.0, TAU, 32, Color(tint, 0.12), maxf(1.0, r * 0.008), true)
		draw_circle(nc + Vector2(r * 0.05, -r * 0.04), r * 0.05, Color(tint, 0.12), true, -1.0, true)


func _draw_planet(c: Vector2, r: float, accent: Color) -> void:
	var m := r * 4.2
	draw_texture_rect(_glow, Rect2(c - Vector2(m, m) * 0.5, Vector2(m, m)), false, Color(1, 1, 1, 0.9))
	var tilt := -0.32
	var orbit_r := Vector2(r * 1.75, r * 0.42)
	var moon_a := _t * 0.12
	var moon := c + Vector2(cos(moon_a) * orbit_r.x, sin(moon_a) * orbit_r.y).rotated(tilt)
	var moon_front := sin(moon_a) > 0.0
	_orbit(c, orbit_r, tilt, PI, TAU, Color(accent, 0.22))
	if not moon_front:
		_moon(moon, r)
	var n := 64
	var disc := PackedVector2Array()
	for i in n:
		disc.append(c + Vector2.from_angle(TAU * float(i) / float(n)) * r)
	draw_circle(c, r, Color("#1d564c"), true, -1.0, true)
	# Drifting continents clipped to the disc.
	var shift := fposmod(_t * 0.018, 2.0)
	var land := Color(accent.lerp(Color("#9ccc5a"), 0.35), 0.5)
	for k in 3:
		var bx := -1.0 + fposmod(float(k) * 0.75 + shift, 2.6)
		var blob := PackedVector2Array()
		for i in 22:
			var a2 := TAU * float(i) / 22.0
			var w := 1.0 + 0.28 * sin(a2 * 3.0 + float(k) * 2.0) + 0.12 * sin(a2 * 5.0 + float(k))
			blob.append(c + (Vector2(bx, -0.35 + 0.42 * float(k)) + Vector2(cos(a2) * 0.32, sin(a2) * 0.2) * w) * r)
		for part in Geometry2D.intersect_polygons(blob, disc):
			draw_colored_polygon(part, land)
			var rim := part.duplicate()
			rim.append(part[0])
			draw_polyline(rim, land, 1.0, true)
	_sphere_shading(c, r)
	draw_arc(c, r, 0.0, TAU, 96, Color(accent, 0.55), maxf(1.5, r * 0.012), true)
	draw_arc(c, r * 1.03, PI * 0.95, PI * 1.6, 32, Color(accent, 0.25), maxf(1.0, r * 0.02), true)
	_orbit(c, orbit_r, tilt, 0.0, PI, Color(accent, 0.5))
	if moon_front:
		_moon(moon, r)


func _orbit(c: Vector2, rr: Vector2, tilt: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := lerpf(a0, a1, float(i) / 40.0)
		var p := c + Vector2(cos(a) * rr.x, sin(a) * rr.y).rotated(tilt)
		pts.append(p)
	draw_polyline(pts, col, maxf(1.0, rr.x * 0.006), true)


func _moon(p: Vector2, r: float) -> void:
	draw_circle(p, r * 0.11, Color("#cfe9e1"), true, -1.0, true)
	draw_circle(p + Vector2(r * 0.035, r * 0.03), r * 0.09, Color(0.05, 0.12, 0.12, 0.45), true, -1.0, true)


## Lambert shading overlay (dark night side + soft highlight) as one triangle mesh.
func _sphere_shading(c: Vector2, r: float) -> void:
	var rings := PackedFloat32Array([0.0, 0.25, 0.45, 0.62, 0.76, 0.87, 0.94, 0.985, 1.0])
	var seg := 48
	var light := Vector3(-0.55, -0.62, 0.56).normalized()
	var pts := PackedVector2Array()
	var dark := PackedColorArray()
	var glow := PackedColorArray()
	for ri in rings.size():
		var d := rings[ri]
		var count := 1 if ri == 0 else seg
		for si in count:
			var dir := Vector2.from_angle(TAU * float(si) / float(seg))
			var nrm := Vector3(dir.x * d, dir.y * d, sqrt(maxf(0.0, 1.0 - d * d)))
			var lam := clampf(nrm.dot(light), 0.0, 1.0)
			pts.append(c + dir * d * r)
			dark.append(Color(0.0, 0.025, 0.025, pow(1.0 - lam, 1.6) * 0.86))
			glow.append(Color(0.85, 1.0, 0.95, pow(lam, 5.0) * 0.28))
	var idx := PackedInt32Array()
	for si in seg:
		idx.append_array([0, 1 + si, 1 + (si + 1) % seg])
	for ri in range(1, rings.size() - 1):
		var a0 := 1 + (ri - 1) * seg
		var b0 := 1 + ri * seg
		for si in seg:
			var s1 := (si + 1) % seg
			idx.append_array([a0 + si, b0 + si, b0 + s1, a0 + si, b0 + s1, a0 + s1])
	var ci := get_canvas_item()
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, dark)
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, glow)
