class_name IconSetUI
extends RefCounted
## Interface icons (playback, files, editing, navigation, view). Drawn in the
## 24-unit grid of IconPainter. Add an icon: append its id to NAMES and a
## branch in `draw`. Use `Icons.draw(...)` / `IconTexture` / `IconView` to render.

const NAMES: Array[StringName] = [
	&"play", &"pause", &"step", &"fast_forward", &"slow", &"undo", &"redo", &"save", &"load",
	&"folder", &"settings", &"close", &"back", &"forward", &"plus", &"minus", &"trash", &"copy",
	&"duplicate", &"lock", &"unlock", &"check", &"home", &"menu", &"edit", &"search", &"info",
	&"warning", &"error", &"help", &"star", &"star_filled", &"grid", &"magnet", &"move", &"rotate",
	&"scale", &"chevron_left", &"chevron_right", &"chevron_up", &"chevron_down", &"exit", &"refresh",
	&"list", &"filter", &"sliders", &"heart", &"dice", &"globe", &"eye", &"eye_off", &"camera",
	&"map", &"layers", &"chart", &"clock", &"pointer", &"sprint",
]


static func draw(p: IconPainter, id: StringName) -> bool:
	match id:
		&"play":
			p.fill(PackedVector2Array([Vector2(7.5, 5), Vector2(19, 12), Vector2(7.5, 19)]))
		&"pause":
			p.frrect(Rect2(6, 5, 4.2, 14), 1.2)
			p.frrect(Rect2(13.8, 5, 4.2, 14), 1.2)
		&"step":
			p.fill(PackedVector2Array([Vector2(5, 5.5), Vector2(14.5, 12), Vector2(5, 18.5)]))
			p.frrect(Rect2(16, 5.5, 3.2, 13), 1.0)
		&"fast_forward":
			p.fill(PackedVector2Array([Vector2(2.5, 6), Vector2(11.5, 12), Vector2(2.5, 18)]))
			p.fill(PackedVector2Array([Vector2(12, 6), Vector2(21, 12), Vector2(12, 18)]))
		&"slow":
			for i in 8:
				var a := TAU * float(i) / 8.0
				p.arc(Vector2(12, 12), 9.0, a + 0.12, a + TAU / 8.0 - 0.28)
			p.fill(PackedVector2Array([Vector2(10, 8.5), Vector2(15.5, 12), Vector2(10, 15.5)]))
		&"undo":
			_undo(p, false)
		&"redo":
			_undo(p, true)
		&"save":
			p.poly(PackedVector2Array([Vector2(5.5, 4), Vector2(16, 4), Vector2(20, 8), Vector2(20, 18.5),
				Vector2(18.5, 20), Vector2(5.5, 20), Vector2(4, 18.5), Vector2(4, 5.5)]), true)
			p.poly(PackedVector2Array([Vector2(7.5, 20), Vector2(7.5, 14), Vector2(16.5, 14), Vector2(16.5, 20)]))
			p.poly(PackedVector2Array([Vector2(8, 4), Vector2(8, 8), Vector2(14, 8)]))
		&"load":
			p.line(Vector2(12, 3.5), Vector2(12, 14.5))
			p.poly(PackedVector2Array([Vector2(7, 10), Vector2(12, 15), Vector2(17, 10)]))
			p.poly(PackedVector2Array([Vector2(4, 15), Vector2(4, 20), Vector2(20, 20), Vector2(20, 15)]))
		&"folder":
			p.poly(PackedVector2Array([Vector2(3.5, 6), Vector2(9.5, 6), Vector2(11.5, 8.5), Vector2(20.5, 8.5),
				Vector2(20.5, 19), Vector2(3.5, 19)]), true)
		&"settings":
			_gear(p)
		&"close":
			p.line(Vector2(6, 6), Vector2(18, 18))
			p.line(Vector2(18, 6), Vector2(6, 18))
		&"back":
			p.line(Vector2(19, 12), Vector2(5.5, 12))
			p.poly(PackedVector2Array([Vector2(11, 6), Vector2(5, 12), Vector2(11, 18)]))
		&"forward":
			p.line(Vector2(5, 12), Vector2(18.5, 12))
			p.poly(PackedVector2Array([Vector2(13, 6), Vector2(19, 12), Vector2(13, 18)]))
		&"plus":
			p.line(Vector2(12, 5), Vector2(12, 19))
			p.line(Vector2(5, 12), Vector2(19, 12))
		&"minus":
			p.line(Vector2(5, 12), Vector2(19, 12))
		&"trash":
			p.line(Vector2(4, 6.5), Vector2(20, 6.5))
			p.poly(PackedVector2Array([Vector2(9, 6.5), Vector2(9, 4), Vector2(15, 4), Vector2(15, 6.5)]))
			p.poly(PackedVector2Array([Vector2(6, 6.5), Vector2(7, 20), Vector2(17, 20), Vector2(18, 6.5)]))
			p.line(Vector2(10, 10.5), Vector2(10, 16.5))
			p.line(Vector2(14, 10.5), Vector2(14, 16.5))
		&"copy":
			p.rrect(Rect2(9, 9, 11.5, 11.5), 2.0)
			_back_sheet(p)
		&"duplicate":
			p.rrect(Rect2(9, 9, 11.5, 11.5), 2.0)
			_back_sheet(p)
			p.line(Vector2(14.75, 12), Vector2(14.75, 17.5))
			p.line(Vector2(12, 14.75), Vector2(17.5, 14.75))
		&"lock":
			p.rrect(Rect2(5, 11, 14, 10), 2.0)
			p.poly(PackedVector2Array([Vector2(8, 11), Vector2(8, 7.5)]))
			p.arc(Vector2(12, 7.5), 4.0, PI, TAU)
			p.line(Vector2(16, 7.5), Vector2(16, 11))
			p.disc(Vector2(12, 16), 1.4)
		&"unlock":
			p.rrect(Rect2(5, 11, 14, 10), 2.0)
			p.line(Vector2(8, 11), Vector2(8, 7.5))
			p.arc(Vector2(12, 7.5), 4.0, PI, TAU * 0.93)
			p.disc(Vector2(12, 16), 1.4)
		&"check":
			p.poly(PackedVector2Array([Vector2(5, 12.5), Vector2(10, 17.5), Vector2(19, 7)]))
		&"home":
			p.poly(PackedVector2Array([Vector2(3.5, 11), Vector2(12, 3.5), Vector2(20.5, 11)]))
			p.poly(PackedVector2Array([Vector2(6, 9.5), Vector2(6, 20), Vector2(18, 20), Vector2(18, 9.5)]))
			p.poly(PackedVector2Array([Vector2(10, 20), Vector2(10, 14.5), Vector2(14, 14.5), Vector2(14, 20)]))
		&"menu":
			for y in [6.0, 12.0, 18.0]:
				p.line(Vector2(4, y), Vector2(20, y))
		&"edit":
			p.poly(PackedVector2Array([Vector2(4, 20), Vector2(5, 15.5), Vector2(15.5, 5), Vector2(19, 8.5),
				Vector2(8.5, 19)]), true)
			p.line(Vector2(13.2, 7.3), Vector2(16.7, 10.8))
		&"search":
			p.ring(Vector2(10.5, 10.5), 6.5)
			p.line(Vector2(15.5, 15.5), Vector2(20, 20))
		&"info":
			p.ring(Vector2(12, 12), 9.0)
			p.line(Vector2(12, 11), Vector2(12, 16.5))
			p.disc(Vector2(12, 7.6), 1.35)
		&"warning":
			p.poly(PackedVector2Array([Vector2(12, 3.5), Vector2(21.5, 20), Vector2(2.5, 20)]), true)
			p.line(Vector2(12, 9.5), Vector2(12, 14))
			p.disc(Vector2(12, 17), 1.3)
		&"error":
			p.poly(_octagon(Vector2(12, 12), 9.5), true)
			p.line(Vector2(9, 9), Vector2(15, 15))
			p.line(Vector2(15, 9), Vector2(9, 15))
		&"help":
			p.ring(Vector2(12, 12), 9.0)
			p.arc(Vector2(12, 9.6), 2.9, PI, PI * 2.5)
			p.line(Vector2(12, 12.5), Vector2(12, 13.6))
			p.disc(Vector2(12, 16.8), 1.3)
		&"star":
			p.poly(IconPainter.star_points(Vector2(12, 12.6), 9.5, 4.3), true)
		&"star_filled":
			p.fill(IconPainter.star_points(Vector2(12, 12.6), 9.8, 4.4))
		&"grid":
			for r in [Rect2(4, 4, 7, 7), Rect2(13, 4, 7, 7), Rect2(4, 13, 7, 7), Rect2(13, 13, 7, 7)]:
				p.rrect(r, 1.5)
		&"magnet":
			_magnet(p)
		&"move":
			p.line(Vector2(12, 3), Vector2(12, 21))
			p.line(Vector2(3, 12), Vector2(21, 12))
			p.arrow_head(Vector2(12, 3), Vector2.UP, 3.8)
			p.arrow_head(Vector2(12, 21), Vector2.DOWN, 3.8)
			p.arrow_head(Vector2(3, 12), Vector2.LEFT, 3.8)
			p.arrow_head(Vector2(21, 12), Vector2.RIGHT, 3.8)
		&"rotate":
			var a1 := deg_to_rad(320.0)
			p.arc(Vector2(12, 12), 8.0, deg_to_rad(40.0), a1)
			var tip := Vector2(12, 12) + Vector2(cos(a1), sin(a1)) * 8.0
			p.arrow_head(tip, Vector2(-sin(a1), cos(a1)), 4.5)
		&"scale":
			p.rrect(Rect2(4, 11, 9, 9), 1.5)
			p.line(Vector2(10, 14), Vector2(20, 4))
			p.poly(PackedVector2Array([Vector2(14, 4), Vector2(20, 4), Vector2(20, 10)]))
		&"chevron_left":
			p.poly(PackedVector2Array([Vector2(15, 5), Vector2(8, 12), Vector2(15, 19)]))
		&"chevron_right":
			p.poly(PackedVector2Array([Vector2(9, 5), Vector2(16, 12), Vector2(9, 19)]))
		&"chevron_up":
			p.poly(PackedVector2Array([Vector2(5, 15), Vector2(12, 8), Vector2(19, 15)]))
		&"chevron_down":
			p.poly(PackedVector2Array([Vector2(5, 9), Vector2(12, 16), Vector2(19, 9)]))
		&"exit":
			p.poly(PackedVector2Array([Vector2(13, 4), Vector2(5, 4), Vector2(5, 20), Vector2(13, 20)]))
			p.line(Vector2(10, 12), Vector2(20.5, 12))
			p.poly(PackedVector2Array([Vector2(16.5, 8), Vector2(20.5, 12), Vector2(16.5, 16)]))
		&"refresh":
			p.arc(Vector2(12, 12), 8.0, deg_to_rad(200.0), deg_to_rad(330.0))
			p.arrow_head(Vector2(12, 12) + Vector2.from_angle(deg_to_rad(330.0)) * 8.0, Vector2.from_angle(deg_to_rad(60.0)), 4.0)
			p.arc(Vector2(12, 12), 8.0, deg_to_rad(20.0), deg_to_rad(150.0))
			p.arrow_head(Vector2(12, 12) + Vector2.from_angle(deg_to_rad(150.0)) * 8.0, Vector2.from_angle(deg_to_rad(240.0)), 4.0)
		&"list":
			for y in [6.0, 12.0, 18.0]:
				p.line(Vector2(9.5, y), Vector2(20, y))
				p.disc(Vector2(4.8, y), 1.4)
		&"filter":
			p.poly(PackedVector2Array([Vector2(3.5, 5), Vector2(20.5, 5), Vector2(14, 12.5), Vector2(14, 19.5),
				Vector2(10, 17.5), Vector2(10, 12.5)]), true)
		&"sliders":
			var knobs := [15.0, 8.0, 13.0]
			for i in 3:
				var y := 6.0 + 6.0 * i
				p.line(Vector2(4, y), Vector2(20, y))
				p.disc(Vector2(knobs[i], y), 2.6)
		&"heart":
			p.fill(_heart_points())
		&"dice":
			p.rrect(Rect2(4, 4, 16, 16), 3.5)
			for d in [Vector2(8.6, 8.6), Vector2(12, 12), Vector2(15.4, 15.4)]:
				p.disc(d, 1.55)
		&"globe":
			p.ring(Vector2(12, 12), 9.0)
			p.ellipse(Vector2(12, 12), 4.0, 9.0)
			p.line(Vector2(3, 12), Vector2(21, 12))
		&"eye":
			_eye(p)
		&"eye_off":
			_eye(p)
			p.line(Vector2(4, 4), Vector2(20, 20))
		&"camera":
			p.rrect(Rect2(3, 7.5, 18, 12.5), 2.5)
			p.poly(PackedVector2Array([Vector2(8, 7.5), Vector2(9.5, 4.5), Vector2(14.5, 4.5), Vector2(16, 7.5)]))
			p.ring(Vector2(12, 13.6), 3.6)
		&"map":
			p.poly(PackedVector2Array([Vector2(3, 6), Vector2(9, 4), Vector2(15, 6), Vector2(21, 4),
				Vector2(21, 18), Vector2(15, 20), Vector2(9, 18), Vector2(3, 20)]), true)
			p.line(Vector2(9, 4), Vector2(9, 18))
			p.line(Vector2(15, 6), Vector2(15, 20))
		&"layers":
			p.poly(PackedVector2Array([Vector2(12, 3), Vector2(21, 8), Vector2(12, 13), Vector2(3, 8)]), true)
			p.poly(PackedVector2Array([Vector2(3, 12.5), Vector2(12, 17.5), Vector2(21, 12.5)]))
			p.poly(PackedVector2Array([Vector2(3, 16.5), Vector2(12, 21.5), Vector2(21, 16.5)]))
		&"chart":
			p.poly(PackedVector2Array([Vector2(4, 3.5), Vector2(4, 20), Vector2(20.5, 20)]))
			p.poly(PackedVector2Array([Vector2(7.5, 15.5), Vector2(11, 10.5), Vector2(14.5, 13.5), Vector2(19.5, 6.5)]))
		&"clock":
			p.ring(Vector2(12, 12), 9.0)
			p.poly(PackedVector2Array([Vector2(12, 6.5), Vector2(12, 12), Vector2(15.5, 14)]))
		&"pointer":
			p.poly(PackedVector2Array([Vector2(6, 3), Vector2(6, 19), Vector2(10, 15.2), Vector2(12.8, 21),
				Vector2(15.4, 19.8), Vector2(12.6, 14.2), Vector2(18, 14)]), true)
		&"sprint":
			p.poly(PackedVector2Array([Vector2(5, 6), Vector2(11, 12), Vector2(5, 18)]))
			p.poly(PackedVector2Array([Vector2(12.5, 6), Vector2(18.5, 12), Vector2(12.5, 18)]))
		_:
			return false
	return true


static func _undo(p: IconPainter, mirror: bool) -> void:
	var m := func(v: Vector2) -> Vector2: return Vector2(24.0 - v.x, v.y) if mirror else v
	p.poly(PackedVector2Array([m.call(Vector2(9, 4)), m.call(Vector2(4, 9)), m.call(Vector2(9, 14))]))
	var path := PackedVector2Array([m.call(Vector2(4, 9))])
	for v in IconPainter.arc_points(Vector2(14.5, 14.25), 5.25, -PI * 0.5, PI * 0.5, 12):
		path.append(m.call(v))
	path.append(m.call(Vector2(10.5, 19.5)))
	p.poly(path)


static func _back_sheet(p: IconPainter) -> void:
	p.poly(PackedVector2Array([Vector2(6, 15), Vector2(5.5, 15), Vector2(4, 13.5), Vector2(4, 5.5),
		Vector2(5.5, 4), Vector2(13.5, 4), Vector2(15, 5.5), Vector2(15, 6)]))


static func _gear(p: IconPainter) -> void:
	var c := Vector2(12, 12)
	var pts := PackedVector2Array()
	var teeth := 8
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		pts.append(c + Vector2.from_angle(a - 0.27) * 7.0)
		pts.append(c + Vector2.from_angle(a - 0.15) * 9.6)
		pts.append(c + Vector2.from_angle(a + 0.15) * 9.6)
		pts.append(c + Vector2.from_angle(a + 0.27) * 7.0)
	p.poly(pts, true)
	p.ring(c, 3.0)


static func _magnet(p: IconPainter) -> void:
	var outer := PackedVector2Array([Vector2(5, 4)])
	outer.append_array(IconPainter.arc_points(Vector2(12, 12), 7.0, PI, 0.0, 16))
	outer.append(Vector2(19, 4))
	outer.append(Vector2(15, 4))
	outer.append_array(IconPainter.arc_points(Vector2(12, 12), 3.0, 0.0, PI, 10))
	outer.append(Vector2(9, 4))
	p.poly(outer, true)
	p.line(Vector2(5, 8), Vector2(9, 8))
	p.line(Vector2(15, 8), Vector2(19, 8))


static func _eye(p: IconPainter) -> void:
	var pts := IconPainter.quad_points(Vector2(2.5, 12), Vector2(12, 3), Vector2(21.5, 12), 14)
	var lower := IconPainter.quad_points(Vector2(21.5, 12), Vector2(12, 21), Vector2(2.5, 12), 14)
	lower.remove_at(0)
	lower.remove_at(lower.size() - 1)
	pts.append_array(lower)
	p.poly(pts, true)
	p.ring(Vector2(12, 12), 3.0)


static func _octagon(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(c + Vector2.from_angle(PI / 8.0 + TAU * float(i) / 8.0) * r)
	return pts


static func _heart_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var t := TAU * float(i) / float(n)
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(12.0 + x * 0.56, 11.2 - y * 0.56))
	return pts
