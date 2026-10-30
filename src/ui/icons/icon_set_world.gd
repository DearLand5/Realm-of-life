class_name IconSetWorld
extends RefCounted
## Nature, biology, weather, control-mode and creature-action icons, in the
## 24-unit grid of IconPainter. See IconSetUI for how to add icons.

const NAMES: Array[StringName] = [
	&"dna", &"leaf", &"paw", &"bug", &"fish", &"bird", &"sun", &"moon", &"cloud", &"rain", &"snow",
	&"wind", &"thermometer", &"drop", &"test", &"experiment", &"library", &"group", &"person",
	&"follow", &"observer", &"symmetry", &"claw", &"jump", &"sound", &"zzz", &"dive", &"egg",
	&"tree", &"mountain", &"cell", &"skull", &"worm", &"spider", &"octopus", &"jellyfish", &"starfish",
	&"shell",
]


static func draw(p: IconPainter, id: StringName) -> bool:
	match id:
		&"dna":
			_dna(p)
		&"leaf":
			var pts := IconPainter.quad_points(Vector2(4.5, 19.5), Vector2(3.5, 5.0), Vector2(19.5, 4.5), 14)
			var back := IconPainter.quad_points(Vector2(19.5, 4.5), Vector2(19.0, 19.0), Vector2(4.5, 19.5), 14)
			back.remove_at(0)
			back.remove_at(back.size() - 1)
			pts.append_array(back)
			p.poly(pts, true)
			p.line(Vector2(3.5, 20.5), Vector2(14, 10))
		&"paw":
			p.disc(Vector2(5.8, 10.6), 2.1)
			p.disc(Vector2(9.6, 6.4), 2.25)
			p.disc(Vector2(14.4, 6.4), 2.25)
			p.disc(Vector2(18.2, 10.6), 2.1)
			var pad := PackedVector2Array()
			for i in 28:
				var a := TAU * float(i) / 28.0
				var r := Vector2(5.2, 4.3) * (1.0 + 0.08 * cos(a * 2.0))
				pad.append(Vector2(12, 16) + Vector2(cos(a) * r.x, sin(a) * r.y))
			p.fill(pad)
		&"bug":
			p.ellipse(Vector2(12, 14.5), 4.8, 6.2)
			p.ring(Vector2(12, 6.6), 2.4)
			p.line(Vector2(12, 8.5), Vector2(12, 20.5))
			for s in [-1.0, 1.0]:
				p.poly(PackedVector2Array([Vector2(12 + 4.5 * s, 11), Vector2(12 + 8.0 * s, 9)]))
				p.poly(PackedVector2Array([Vector2(12 + 4.8 * s, 15), Vector2(12 + 8.5 * s, 15)]))
				p.poly(PackedVector2Array([Vector2(12 + 4.2 * s, 18.5), Vector2(12 + 7.5 * s, 21)]))
				p.line(Vector2(12 + 1.2 * s, 4.6), Vector2(12 + 3.2 * s, 2.5))
		&"fish":
			var body := IconPainter.quad_points(Vector2(2.5, 12), Vector2(9.0, 3.5), Vector2(16.5, 12), 14)
			var low := IconPainter.quad_points(Vector2(16.5, 12), Vector2(9.0, 20.5), Vector2(2.5, 12), 14)
			low.remove_at(0)
			low.remove_at(low.size() - 1)
			body.append_array(low)
			p.poly(body, true)
			p.poly(PackedVector2Array([Vector2(16.5, 12), Vector2(21.5, 7.5), Vector2(21.5, 16.5)]), true)
			p.disc(Vector2(7.0, 10.6), 1.2)
		&"bird":
			var wing_l := IconPainter.quad_points(Vector2(2.0, 9.5), Vector2(8.0, 4.5), Vector2(12.0, 13.0), 12)
			var wing_r := IconPainter.quad_points(Vector2(12.0, 13.0), Vector2(16.0, 4.5), Vector2(22.0, 9.5), 12)
			wing_r.remove_at(0)
			wing_l.append_array(wing_r)
			p.poly(wing_l)
			p.poly(PackedVector2Array([Vector2(10.5, 16.5), Vector2(12, 19), Vector2(13.5, 16.5)]))
		&"sun":
			p.ring(Vector2(12, 12), 4.2)
			for i in 8:
				var d := Vector2.from_angle(TAU * float(i) / 8.0)
				p.line(Vector2(12, 12) + d * 7.2, Vector2(12, 12) + d * 9.8)
		&"moon":
			_moon(p)
		&"cloud":
			p.poly(_cloud_points(Vector2(0, 0.5), 1.0), true)
		&"rain":
			p.poly(_cloud_points(Vector2(0, -3.0), 0.85), true)
			for x in [8.0, 12.0, 16.0]:
				p.line(Vector2(x, 16.5), Vector2(x - 1.5, 21))
		&"snow":
			for i in 3:
				var d := Vector2.from_angle(PI * 0.5 + PI * float(i) / 3.0)
				p.line(Vector2(12, 12) - d * 9.0, Vector2(12, 12) + d * 9.0)
				for s in [-1.0, 1.0]:
					var tip: Vector2 = Vector2(12, 12) + d * 9.0 * float(s)
					p.arrow_head(tip - d * 2.6 * float(s), -d * float(s), 2.6, 50.0)
		&"wind":
			p.line(Vector2(2.5, 12), Vector2(18.5, 12))
			p.arc(Vector2(18.5, 9.5), 2.5, PI * 0.5, -PI * 0.85)
			p.line(Vector2(2.5, 8), Vector2(10.5, 8))
			p.arc(Vector2(10.5, 6.0), 2.0, PI * 0.5, -PI * 0.85)
			p.line(Vector2(2.5, 16), Vector2(13.5, 16))
			p.arc(Vector2(13.5, 18.0), 2.0, -PI * 0.5, PI * 0.85)
		&"thermometer":
			_thermometer(p)
		&"drop":
			_drop(p)
		&"test":
			p.line(Vector2(8.5, 3.5), Vector2(15.5, 3.5))
			p.poly(PackedVector2Array([Vector2(10, 3.5), Vector2(10, 9.5), Vector2(4.5, 18.8), Vector2(5.6, 20.5),
				Vector2(18.4, 20.5), Vector2(19.5, 18.8), Vector2(14, 9.5), Vector2(14, 3.5)]))
			p.line(Vector2(7.2, 15), Vector2(16.8, 15))
		&"experiment":
			for i in 3:
				p.ellipse(Vector2(12, 12), 9.6, 3.6, PI * float(i) / 3.0)
			p.disc(Vector2(12, 12), 1.9)
		&"library":
			p.poly(PackedVector2Array([Vector2(12, 6.5), Vector2(9, 5), Vector2(3, 5), Vector2(3, 18.5),
				Vector2(9, 18.5), Vector2(12, 20)]))
			p.poly(PackedVector2Array([Vector2(12, 6.5), Vector2(15, 5), Vector2(21, 5), Vector2(21, 18.5),
				Vector2(15, 18.5), Vector2(12, 20)]))
			p.line(Vector2(12, 6.5), Vector2(12, 20))
		&"group":
			p.ring(Vector2(9, 8.2), 3.3)
			p.arc(Vector2(9, 20.5), 6.2, PI, TAU)
			p.arc(Vector2(16.2, 7.8), 2.8, -PI * 0.55, PI * 0.6)
			p.arc(Vector2(16.5, 19.5), 5.2, -PI * 0.45, 0.0)
		&"person":
			p.ring(Vector2(12, 7.5), 3.8)
			p.arc(Vector2(12, 21.5), 7.5, PI, TAU)
		&"follow":
			p.ring(Vector2(12, 7.0), 2.9)
			p.arc(Vector2(12, 17.5), 5.0, PI, TAU)
			var e0 := deg_to_rad(15.0)
			var e1 := deg_to_rad(165.0)
			var pts := PackedVector2Array()
			for i in 17:
				var a := lerpf(e0, e1, float(i) / 16.0)
				pts.append(Vector2(12, 17.5) + Vector2(cos(a) * 10.0, sin(a) * 4.0))
			p.poly(pts)
			p.arrow_head(pts[pts.size() - 1], pts[pts.size() - 1] - pts[pts.size() - 3], 3.4)
		&"observer":
			p.ring(Vector2(6.8, 16), 3.9)
			p.ring(Vector2(17.2, 16), 3.9)
			p.poly(PackedVector2Array([Vector2(3.2, 14.5), Vector2(5, 6), Vector2(9.5, 6), Vector2(10.7, 14)]))
			p.poly(PackedVector2Array([Vector2(20.8, 14.5), Vector2(19, 6), Vector2(14.5, 6), Vector2(13.3, 14)]))
			p.line(Vector2(10.7, 11), Vector2(13.3, 11))
		&"symmetry":
			p.dashed_line(Vector2(12, 2.5), Vector2(12, 21.5), 2.0, 2.2)
			p.fill(PackedVector2Array([Vector2(9.5, 6), Vector2(9.5, 18), Vector2(3, 18)]))
			p.poly(PackedVector2Array([Vector2(14.5, 6), Vector2(14.5, 18), Vector2(21, 18)]), true)
		&"claw":
			for i in 3:
				var o := 4.6 * float(i)
				p.poly(IconPainter.quad_points(Vector2(9.5 + o, 3.5), Vector2(10.0 + o, 13.0), Vector2(3.5 + o, 20.5), 10))
		&"jump":
			p.line(Vector2(12, 17), Vector2(12, 4))
			p.poly(PackedVector2Array([Vector2(6.5, 9.5), Vector2(12, 4), Vector2(17.5, 9.5)]))
			p.line(Vector2(4.5, 20.5), Vector2(19.5, 20.5))
		&"sound":
			p.poly(PackedVector2Array([Vector2(3, 9.5), Vector2(7, 9.5), Vector2(11.5, 5.5), Vector2(11.5, 18.5),
				Vector2(7, 14.5), Vector2(3, 14.5)]), true)
			p.arc(Vector2(12, 12), 4.2, -0.8, 0.8)
			p.arc(Vector2(12, 12), 8.2, -0.85, 0.85)
		&"zzz":
			p.poly(PackedVector2Array([Vector2(3.5, 12), Vector2(10.5, 12), Vector2(3.5, 19.5), Vector2(10.5, 19.5)]))
			p.poly(PackedVector2Array([Vector2(13, 6.5), Vector2(18, 6.5), Vector2(13, 12), Vector2(18, 12)]))
			p.poly(PackedVector2Array([Vector2(18.5, 2.5), Vector2(21.5, 2.5), Vector2(18.5, 6), Vector2(21.5, 6)]))
		&"dive":
			p.line(Vector2(12, 2.5), Vector2(12, 12.5))
			p.poly(PackedVector2Array([Vector2(8, 8.8), Vector2(12, 12.8), Vector2(16, 8.8)]))
			p.poly(_wave(16.5))
			p.poly(_wave(20.5))
		&"egg":
			var pts := PackedVector2Array()
			for i in 36:
				var a := TAU * float(i) / 36.0
				var ry := 8.6 if sin(a) < 0.0 else 7.0
				pts.append(Vector2(12 + cos(a) * 6.6 * (1.0 - 0.12 * maxf(-sin(a), 0.0)), 13.5 + sin(a) * ry))
			p.poly(pts, true)
		&"tree":
			p.ring(Vector2(12, 9), 6.3)
			p.line(Vector2(12, 12), Vector2(12, 21))
			p.line(Vector2(12, 15.5), Vector2(15, 12.5))
			p.line(Vector2(8, 21), Vector2(16, 21))
		&"mountain":
			p.poly(PackedVector2Array([Vector2(2, 20), Vector2(9, 7), Vector2(13.5, 14.5), Vector2(16, 10.5),
				Vector2(22, 20)]), true)
			p.poly(PackedVector2Array([Vector2(6.5, 11.6), Vector2(8.3, 12.8), Vector2(9.6, 11.4), Vector2(11.2, 12.3)]))
		&"cell":
			p.ellipse(Vector2(12, 12), 9.5, 8.0, -0.3)
			p.ring(Vector2(10.5, 11.5), 3.0)
			p.disc(Vector2(10.5, 11.5), 1.2)
			p.disc(Vector2(16, 9), 1.0)
			p.disc(Vector2(15.5, 15.5), 1.2)
		&"skull":
			var top := IconPainter.arc_points(Vector2(12, 11), 8.0, PI * 0.82, PI * 2.18, 24)
			top.append(Vector2(16.5, 20.5))
			top.append(Vector2(7.5, 20.5))
			p.poly(top, true)
			p.disc(Vector2(8.8, 11.8), 2.0)
			p.disc(Vector2(15.2, 11.8), 2.0)
			p.line(Vector2(12, 20.5), Vector2(12, 17.5))
		&"worm":
			var pts := PackedVector2Array()
			for i in 25:
				var t := float(i) / 24.0
				pts.append(Vector2(lerpf(3.0, 19.5, t), 13.0 + sin(t * TAU * 1.25) * 4.0))
			p.width = 3.2
			p.poly(pts)
			p.disc(Vector2(20.2, 13.0 + sin(TAU * 1.25) * 4.0), 2.3)
		&"spider":
			p.disc(Vector2(12, 14.5), 3.6)
			p.disc(Vector2(12, 9.0), 2.2)
			for sgn in [-1.0, 1.0]:
				var k := float(sgn)
				for j in 4:
					var y := 11.5 + float(j) * 2.0
					var knee := Vector2(12 + k * (6.5 + float(j) * 0.4), y - 3.5 + float(j) * 0.8)
					var foot := Vector2(12 + k * (9.5 + float(j) * 0.3), y + 2.5 + float(j) * 1.4)
					p.poly(PackedVector2Array([Vector2(12 + k * 2.5, y), knee, foot]))
		&"octopus":
			var head := IconPainter.arc_points(Vector2(12, 10), 6.5, PI, TAU, 18)
			p.poly(head)
			p.line(Vector2(5.5, 10), Vector2(5.5, 13))
			p.line(Vector2(18.5, 10), Vector2(18.5, 13))
			for j in 4:
				var x0 := 7.0 + float(j) * 3.33
				var tent := PackedVector2Array()
				for i in 9:
					var t := float(i) / 8.0
					tent.append(Vector2(x0 + sin(t * PI * 1.6 + float(j)) * 1.6, lerpf(13.0, 21.0, t)))
				p.poly(tent)
			p.disc(Vector2(9.7, 9.5), 1.0)
			p.disc(Vector2(14.3, 9.5), 1.0)
		&"jellyfish":
			var bell := IconPainter.arc_points(Vector2(12, 11), 8.0, PI, TAU, 20)
			p.poly(bell, true)
			for j in 4:
				var x0 := 6.5 + float(j) * 3.66
				var tr := PackedVector2Array()
				for i in 9:
					var t := float(i) / 8.0
					tr.append(Vector2(x0 + sin(t * TAU + float(j)) * 0.9, lerpf(11.5, 21.5 - absf(1.5 - float(j)) * 1.5, t)))
				p.poly(tr)
		&"starfish":
			p.poly(IconPainter.star_points(Vector2(12, 12.6), 10.0, 4.6), true)
			p.disc(Vector2(12, 12.6), 1.3)
		&"shell":
			var dome := IconPainter.arc_points(Vector2(11, 15), 7.5, PI, TAU, 20)
			p.poly(dome, true)
			p.poly(PackedVector2Array([Vector2(7.2, 15), Vector2(9, 10.5), Vector2(13, 10.5), Vector2(14.8, 15)]))
			p.line(Vector2(11, 7.5), Vector2(11, 10.5))
			p.ring(Vector2(20.3, 13.2), 1.9)
			p.line(Vector2(6, 15), Vector2(5, 18.5))
			p.line(Vector2(16, 15), Vector2(17, 18.5))
		_:
			return false
	return true


static func _dna(p: IconPainter) -> void:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var t := float(i) / float(n)
		var y := lerpf(3.0, 21.0, t)
		var w := cos(t * TAU) * 5.5
		a.append(Vector2(12.0 + w, y))
		b.append(Vector2(12.0 - w, y))
	p.poly(a)
	p.poly(b)
	for t in [0.07, 0.43, 0.57, 0.93]:
		var y := lerpf(3.0, 21.0, t)
		var half := absf(cos(t * TAU) * 5.5) - 1.8
		if half > 0.4:
			p.line(Vector2(12.0 - half, y), Vector2(12.0 + half, y))


static func _moon(p: IconPainter) -> void:
	var c1 := Vector2(12, 12.5)
	var r1 := 8.6
	var c2 := Vector2(16.8, 8.0)
	var r2 := 7.0
	var ang := IconPainter.circle_intersection_angles(c1, r1, c2, r2)
	if ang.is_empty():
		p.ring(c1, r1)
		return
	# Outer arc: the long way round, away from the second circle.
	var pts := IconPainter.arc_points(c1, r1, ang[1], ang[0] + TAU, 28)
	var q0 := c1 + Vector2.from_angle(ang[0]) * r1
	var q1 := c1 + Vector2.from_angle(ang[1]) * r1
	var b0 := (q0 - c2).angle()
	var b1 := (q1 - c2).angle()
	while b1 < b0:
		b1 += TAU
	var inner := IconPainter.arc_points(c2, r2, b0, b1, 16)
	inner.reverse()
	inner.remove_at(0)
	inner.remove_at(inner.size() - 1)
	# Inner arc must run the short way, facing c1.
	var mid: Vector2 = inner[inner.size() / 2] if inner.size() > 0 else c2
	if mid.distance_to(c1) > r1:
		inner = IconPainter.arc_points(c2, r2, b1, b0 + TAU, 16)
		inner.remove_at(0)
		inner.remove_at(inner.size() - 1)
	pts.append_array(inner)
	p.poly(pts, true)


## Three-lobed cloud outline (union of circles over a flat base), offset by
## `o`, scaled around (12, 14) by `sc`.
static func _cloud_points(o: Vector2, sc: float) -> PackedVector2Array:
	var circles := [Vector3(7.2, 14.8, 4.2), Vector3(12.6, 10.8, 5.6), Vector3(17.4, 14.6, 4.4)]
	var base_y := 19.0
	var centre := Vector2(12.2, 14.6)
	var pts: Array[Vector2] = []
	for ci in circles.size():
		var cc: Vector3 = circles[ci]
		for i in 48:
			var v := Vector2(cc.x, cc.y) + Vector2.from_angle(TAU * float(i) / 48.0) * cc.z
			if v.y > base_y + 0.01:
				continue
			var inside := false
			for cj in circles.size():
				if cj == ci:
					continue
				var oc: Vector3 = circles[cj]
				if v.distance_to(Vector2(oc.x, oc.y)) < oc.z - 0.05:
					inside = true
					break
			if not inside and not (v.x > 7.2 and v.x < 17.4 and v.y > 14.6):
				pts.append(v)
	for i in 9:
		pts.append(Vector2(lerpf(7.2, 17.4, float(i) / 8.0), base_y))
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return (a - centre).angle() < (b - centre).angle())
	var out := PackedVector2Array()
	var c := Vector2(12, 14)
	for v in pts:
		out.append(c + (v - c) * sc + o)
	return out


static func _thermometer(p: IconPainter) -> void:
	var bulb := Vector2(12, 17.6)
	var br := 3.7
	var dy := sqrt(br * br - 2.4 * 2.4)
	var path := PackedVector2Array([Vector2(9.6, bulb.y - dy), Vector2(9.6, 5.4)])
	path.append_array(IconPainter.arc_points(Vector2(12, 5.4), 2.4, PI, TAU, 10))
	path.append(Vector2(14.4, bulb.y - dy))
	var a0 := atan2(-dy, 2.4)
	path.append_array(IconPainter.arc_points(bulb, br, a0, PI - a0, 18))
	p.poly(path, true)
	p.disc(bulb, 1.7)
	p.line(Vector2(12, 16.5), Vector2(12, 9.5))


static func _drop(p: IconPainter) -> void:
	var c := Vector2(12, 14.8)
	var r := 6.2
	var apex := Vector2(12, 2.8)
	var d := apex.distance_to(c)
	var off := acos(r / d)
	var up := -PI * 0.5
	var path := PackedVector2Array([apex])
	path.append_array(IconPainter.arc_points(c, r, up + off, up - off + TAU, 24))
	p.poly(path, true)


static func _wave(y: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		var x := lerpf(3.0, 21.0, float(i) / 16.0)
		pts.append(Vector2(x, y + sin(float(i) / 16.0 * TAU * 1.5) * 1.3))
	return pts
