class_name MenuBackground
extends Control
## Light animated backdrop for the main menu: deep teal gradient with soft
## glows, slowly drifting translucent "cells" (wobbling organic blobs with
## nuclei) and rising spores. Pure 2D, redrawn at ≤ 30 fps (≤ 15 fps with
## battery saver) and paused when hidden.

const BLOBS := 7
const SPORES := 46

var time_scale: float = 1.0

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
			"r": rng.range_f(0.07, 0.2), "ph": rng.range_f(0, TAU), "spin": rng.range_f(-0.15, 0.15),
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
	var tints := [accent, Color("#58b7f0"), Color("#f2c063")]
	for b in _blobs:
		_draw_blob(b, sz, m, tints[int(b["hue"])])
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
		var w := 1.0 + 0.07 * sin(a * 3.0 + _t * 0.7 + ph) + 0.05 * sin(a * 5.0 - _t * 0.5 + ph * 2.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * w)
	draw_colored_polygon(pts, Color(tint, 0.055))
	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, Color(tint, 0.16), maxf(1.0, r * 0.012), true)
	if b["nuc"]:
		var nc := c + Vector2(cos(ph + _t * 0.2), sin(ph + _t * 0.2)) * r * 0.25
		draw_circle(nc, r * 0.22, Color(tint, 0.07), true, -1.0, true)
		draw_arc(nc, r * 0.22, 0.0, TAU, 32, Color(tint, 0.18), maxf(1.0, r * 0.01), true)
		draw_circle(nc + Vector2(r * 0.05, -r * 0.04), r * 0.06, Color(tint, 0.16), true, -1.0, true)
