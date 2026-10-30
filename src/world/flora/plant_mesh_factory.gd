class_name PlantMeshFactory
extends RefCounted
## Procedural plant meshes per growth form with 3 LODs (0 near .. 2 far).
## Trunks/stems are tubes; foliage are alpha-scissor cards whose leaf shapes
## are drawn in shaders/plant.gdshader. Deterministic per species seed.
## Meshes are built at the species' adult height (instances scale ±25 %).

const LODS := 3
const K := PlantMeshBuilder.Kind

static var _cache: Dictionary = {}


static func get_mesh(sp: PlantSpecies, lod: int) -> ArrayMesh:
	var key := "%d|%s|%.2f|%d" % [sp.seed_value, sp.form, sp.height, lod]
	if _cache.has(key):
		return _cache[key]
	var m := build(sp, clampi(lod, 0, LODS - 1))
	_cache[key] = m
	return m


static func clear_cache() -> void:
	_cache.clear()


static func build(sp: PlantSpecies, lod: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = sp.seed_value * 7 + 13
	var b := PlantMeshBuilder.new(sp.height)
	match sp.form:
		&"broadleaf_tree":
			_broadleaf(b, sp, lod, rng)
		&"conifer":
			_conifer(b, sp, lod, rng)
		&"palm":
			_palm(b, sp, lod, rng)
		&"shrub":
			_shrub(b, sp, lod, rng)
		&"cactus":
			_cactus(b, sp, lod, rng)
		&"fern":
			_fern(b, sp, lod, rng)
		&"reed":
			_reed(b, sp, lod, rng)
		&"flower":
			_flower(b, sp, lod, rng)
		&"mushroom":
			_mushroom(b, sp, lod, rng)
		&"kelp", &"algae":
			_ribbons(b, sp, lod, rng)
		_:
			_grass(b, sp, lod, rng)
	return b.commit()


# --- Trees -----------------------------------------------------------------------

static func _broadleaf(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var flat := sp.temp_opt > 21.0 and sp.moist_opt < 0.55    # savanna acacia
	var tall := sp.temp_opt > 20.0 and sp.moist_opt >= 0.55   # jungle emergent
	var trunk_h := h * (rng.randf_range(0.55, 0.62) if flat else (rng.randf_range(0.5, 0.6) if tall else rng.randf_range(0.34, 0.44)))
	var cr := h * (rng.randf_range(0.42, 0.5) if flat else (rng.randf_range(0.27, 0.32) if tall else rng.randf_range(0.28, 0.34)))
	var ch := h - trunk_h
	if flat:
		ch = h * 0.24
	var r0 := h * 0.032
	var sides: int = [7, 5, 4][lod]
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * h * 0.03
	var trunk := PackedVector3Array([Vector3.ZERO, Vector3(0, trunk_h * 0.35, 0) + lean * 0.3, Vector3(0, trunk_h * 0.7, 0) + lean * 0.7, Vector3(0, trunk_h, 0) + lean])
	var tr := PackedFloat32Array([r0 * 1.45, r0 * 1.05, r0 * 0.9, r0 * 0.75])
	if lod == 2:
		trunk = PackedVector3Array([trunk[0], trunk[3] + Vector3(0, ch * 0.3, 0)])
		tr = PackedFloat32Array([r0 * 1.2, r0 * 0.6])
	b.tube(trunk, tr, sides)
	var crown_c := Vector3(lean.x, trunk_h + ch * 0.5, lean.z)
	if flat:
		crown_c.y = h - ch * 0.55
	# Main branches from the trunk top towards the crown shell.
	if lod < 2:
		var n_main := rng.randi_range(4, 6) if lod == 0 else 3
		for k in n_main:
			var a := (float(k) + rng.randf_range(-0.3, 0.3)) / float(n_main) * TAU
			var out := Vector3(cos(a), 0, sin(a))
			var rise := rng.randf_range(0.15, 0.45) if flat else rng.randf_range(0.5, 1.0)
			var start := Vector3(0, trunk_h * rng.randf_range(0.82, 1.0), 0) + lean
			var tip := crown_c + out * cr * 0.8 + Vector3(0, ch * (rise - 0.55) * 0.6, 0)
			var mid := start.lerp(tip, 0.5) + Vector3(0, ch * 0.08, 0)
			b.tube(PackedVector3Array([start, mid, tip]), PackedFloat32Array([r0 * 0.55, r0 * 0.35, r0 * 0.14]), 3 if lod == 1 else 4)
			if lod == 0:
				var sub_a := a + rng.randf_range(0.6, 1.0) * (1.0 if k % 2 == 0 else -1.0)
				var sub_tip := mid + Vector3(cos(sub_a), 0.55, sin(sub_a)) * cr * 0.45
				b.tube(PackedVector3Array([mid, sub_tip]), PackedFloat32Array([r0 * 0.25, r0 * 0.08]), 3)
	# Leaf cluster cards on the crown ellipsoid.
	var n_cards: int = [42, 18, 8][lod]
	var size_mul: float = [1.0, 1.45, 2.1][lod]
	var radii := Vector3(cr, ch * 0.5, cr)
	for k in n_cards:
		var dir := _fib_dir(k, n_cards, rng)
		var depth := rng.randf_range(0.55, 1.0) if lod == 0 else rng.randf_range(0.45, 0.85)
		var p := crown_c + Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * depth
		var s := cr * rng.randf_range(0.85, 1.1) * size_mul
		_leaf_card(b, p, dir, s, crown_c, radii, K.LEAF, rng)


static func _conifer(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var r0 := h * 0.026
	var base_r := h * rng.randf_range(0.2, 0.25)
	if lod == 2:
		# Far: crossed silhouette cards + short trunk.
		b.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, h * 0.25, 0)]), PackedFloat32Array([r0 * 1.2, r0]), 3)
		for k in 2:
			var a := float(k) * PI * 0.5 + rng.randf_range(0, 0.4)
			var right := Vector3(cos(a), 0, sin(a)) * base_r * 2.2
			var nrm := Vector3(-sin(a), 0.6, cos(a))
			b.card(Vector3(0, h * 0.08, 0), right, Vector3(0, h * 0.94, 0), K.SILHOUETTE, nrm, 0.6, 1.0, rng.randf())
		return
	b.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h * 0.97, 0)]), PackedFloat32Array([r0 * 1.4, r0 * 0.7, r0 * 0.12]), 6 if lod == 0 else 4)
	var tiers: int = 9 if lod == 0 else 5
	var per: int = 6 if lod == 0 else 4
	var y0 := h * rng.randf_range(0.14, 0.2)
	var y1 := h * 0.93
	for t in tiers:
		var f := float(t) / float(tiers - 1)
		var y := lerpf(y0, y1, pow(f, 0.85))
		var r := base_r * pow(1.0 - f, 0.95) + h * 0.03
		var droop := r * rng.randf_range(0.35, 0.5)
		for k in per:
			var a := (float(k) + float(t) * 0.618 * float(per) + rng.randf_range(-0.2, 0.2)) / float(per) * TAU
			var out := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-sin(a), 0, cos(a))
			var w := r * (1.05 if lod == 0 else 1.4)
			var length_v := out * r * 1.1 + Vector3(0, -droop, 0)
			var nrm := (out * 0.5 + Vector3.UP).normalized()
			b.card(Vector3(0, y + droop * 0.25, 0), side * w, length_v, K.NEEDLE, nrm, lerpf(0.6, 0.85, f), 1.0, rng.randf())
	# Leader at the top.
	var tip_w := h * 0.06
	b.card(Vector3(0, y1 - h * 0.02, 0), Vector3(tip_w, 0, 0), Vector3(0, h * 0.09, 0), K.NEEDLE, Vector3.UP, 0.8, 1.0, 0.5)
	b.card(Vector3(0, y1 - h * 0.02, 0), Vector3(0, 0, tip_w), Vector3(0, h * 0.09, 0), K.NEEDLE, Vector3.UP, 0.8, 1.0, 0.5)


static func _palm(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var lean_dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var lean := h * rng.randf_range(0.08, 0.2)
	var segs: int = [6, 4, 2][lod]
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in segs + 1:
		var t := float(k) / float(segs)
		path.append(Vector3(0, h * 0.92 * t, 0) + lean_dir * lean * t * t)
		radii.append(h * lerpf(0.04, 0.026, t))
	b.tube(path, radii, [6, 5, 3][lod])
	var top := path[path.size() - 1]
	var n_fronds: int = [9, 6, 5][lod]
	var flen := h * rng.randf_range(0.42, 0.5)
	for k in n_fronds:
		var a := (float(k) + rng.randf_range(-0.25, 0.25)) / float(n_fronds) * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var lift := rng.randf_range(0.2, 0.55)
		var pts := PackedVector3Array()
		var hw := PackedVector3Array()
		var n_pts: int = [5, 3, 2][lod]
		for j in n_pts:
			var t := float(j) / float(n_pts - 1)
			pts.append(top + out * flen * t + Vector3(0, (lift * t - 0.75 * t * t) * flen, 0))
			hw.append(side * flen * 0.2 * (0.55 + 0.45 * sin(PI * clampf(t * 1.1, 0.0, 1.0))))
		b.strip(pts, hw, K.FROND, Vector3.UP, 0.7, 1.0, rng.randf())


# --- Low plants --------------------------------------------------------------------

static func _shrub(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var c := Vector3(0, h * 0.52, 0)
	var radii := Vector3(h * 0.6, h * 0.48, h * 0.6)
	if lod == 0:
		for k in 4:
			var a := float(k) / 4.0 * TAU + rng.randf_range(-0.4, 0.4)
			var tip := c + Vector3(cos(a) * radii.x * 0.6, rng.randf_range(0.0, 0.3) * h, sin(a) * radii.z * 0.6)
			b.tube(PackedVector3Array([Vector3.ZERO, tip]), PackedFloat32Array([h * 0.025, h * 0.008]), 3)
	var n_cards: int = [13, 7, 4][lod]
	var size_mul: float = [1.0, 1.3, 1.7][lod]
	for k in n_cards:
		var dir := _fib_dir(k, n_cards, rng)
		dir.y = absf(dir.y) * 0.8 + 0.1 if dir.y < -0.5 else dir.y
		var p := c + Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * rng.randf_range(0.45, 0.9)
		_leaf_card(b, p, dir, h * rng.randf_range(0.5, 0.65) * size_mul, c, radii, K.LEAF, rng)


static func _grass(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var n: int = [4, 3, 2][lod]
	for k in n:
		var a := float(k) / float(n) * PI + rng.randf_range(-0.25, 0.25)
		var right := Vector3(cos(a), 0, sin(a)) * h * rng.randf_range(1.0, 1.3)
		var out := Vector3(-sin(a), 0, cos(a)) * h * 0.12 * (1.0 if k % 2 == 0 else -1.0)
		var nrm := Vector3(0, 1, 0) + out.normalized() * 0.3
		b.card(Vector3.ZERO, right, Vector3(0, h, 0) + out, K.GRASS, nrm, 0.8, 1.0, rng.randf())


static func _flower(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var stems: int = [3, 2, 1][lod]
	for k in stems:
		var a := float(k) / float(stems) * PI + rng.randf_range(-0.3, 0.3)
		var right := Vector3(cos(a), 0, sin(a)) * h * 0.55
		b.card(Vector3.ZERO, right, Vector3(0, h * 0.85, 0), K.GRASS, Vector3.UP, 0.6, 1.0, rng.randf())
	var heads: int = [4, 2, 1][lod]
	for k in heads:
		var a := rng.randf() * TAU
		var r := h * rng.randf_range(0.0, 0.18)
		var p := Vector3(cos(a) * r, h * rng.randf_range(0.75, 1.0), sin(a) * r)
		var s := h * rng.randf_range(0.28, 0.36) * (1.0 + 0.3 * float(lod))
		var tilt := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
		var right := tilt.cross(Vector3.FORWARD).normalized() * s
		var up := right.cross(tilt).normalized() * s
		b.card_centered(p, right, up, K.PETAL, tilt, 1.0, rng.randf())


static func _fern(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var n: int = [8, 5, 4][lod]
	var flen := h * 1.15
	for k in n:
		var a := (float(k) + rng.randf_range(-0.3, 0.3)) / float(n) * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var rise := rng.randf_range(1.2, 1.7)
		var pts := PackedVector3Array()
		var hw := PackedVector3Array()
		var n_pts: int = [4, 3, 2][lod]
		for j in n_pts:
			var t := float(j) / float(n_pts - 1)
			pts.append(out * flen * 0.75 * t + Vector3(0, (rise * t - 0.95 * t * t) * h, 0))
			hw.append(side * flen * 0.17 * (0.6 + 0.4 * sin(PI * clampf(t * 1.15, 0.0, 1.0))))
		b.strip(pts, hw, K.FROND, Vector3.UP, 0.5, 1.0, rng.randf())


static func _reed(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var n: int = [9, 5, 3][lod]
	for k in n:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * h * rng.randf_range(0.0, 0.12)
		var bh := h * rng.randf_range(0.7, 1.0)
		var bend := Vector3(cos(a), 0, sin(a)) * bh * rng.randf_range(0.05, 0.22)
		var side := Vector3(-sin(a), 0, cos(a)) * h * 0.025
		var pts := PackedVector3Array([base, base + Vector3(0, bh * 0.55, 0) + bend * 0.3, base + Vector3(0, bh, 0) + bend])
		b.strip(pts, PackedVector3Array([side, side * 0.8, side * 0.2]), K.BLADE, Vector3.UP, 0.55, 1.0, rng.randf())
	if lod < 2:
		for k in 2:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * h * 0.08
			var top := p + Vector3(0, h * 1.05, 0)
			b.tube(PackedVector3Array([p, top - Vector3(0, h * 0.14, 0)]), PackedFloat32Array([h * 0.006, h * 0.005]), 3, K.STEM)
			b.tube(PackedVector3Array([top - Vector3(0, h * 0.14, 0), top]), PackedFloat32Array([h * 0.022, h * 0.02]), 5 if lod == 0 else 3, K.HEAD)


static func _cactus(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var r := h * rng.randf_range(0.08, 0.11)
	var sides: int = [10, 7, 5][lod]
	b.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h * 0.88, 0), Vector3(0, h * 0.97, 0), Vector3(0, h, 0)]),
		PackedFloat32Array([r * 0.9, r, r, r * 0.75, r * 0.2]), sides, K.CACTUS, 0.7)
	if lod == 2:
		return
	var arms := rng.randi_range(1, 3)
	for k in arms:
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var y := h * rng.randf_range(0.3, 0.55)
		var ar := r * 0.62
		var reach := h * rng.randf_range(0.14, 0.2)
		var up_len := h * rng.randf_range(0.22, 0.34)
		var p0 := Vector3(0, y, 0)
		var path := PackedVector3Array([p0, p0 + out * reach * 0.7 + Vector3(0, ar * 0.3, 0), p0 + out * reach + Vector3(0, ar * 1.4, 0),
			p0 + out * reach + Vector3(0, up_len * 0.85, 0), p0 + out * reach + Vector3(0, up_len, 0)])
		b.tube(path, PackedFloat32Array([ar, ar, ar, ar * 0.75, ar * 0.2]), maxi(sides - 2, 4), K.CACTUS, 0.75)
	if lod == 0:
		var fs := r * 1.3
		b.card_centered(Vector3(0, h + fs * 0.1, 0), Vector3(fs, 0, 0), Vector3(0, 0, fs), K.PETAL, Vector3.UP, 1.0, 0.3)


static func _mushroom(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var count: int = [3, 2, 1][lod]
	var sides: int = [9, 7, 5][lod]
	for k in count:
		var s := 1.0 if k == 0 else rng.randf_range(0.5, 0.8)
		var off := Vector3.ZERO if k == 0 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * h * rng.randf_range(0.35, 0.6)
		var sh := h * s
		var cap_r := sh * rng.randf_range(0.45, 0.6)
		b.tube(PackedVector3Array([off, off + Vector3(0, sh * 0.82, 0)]), PackedFloat32Array([sh * 0.09, sh * 0.07]), maxi(sides - 3, 4), K.STEM, 0.7)
		var prof := PackedVector2Array([Vector2(0.0, sh), Vector2(cap_r * 0.55, sh * 0.96), Vector2(cap_r * 0.92, sh * 0.82), Vector2(cap_r, sh * 0.72), Vector2(cap_r * 0.8, sh * 0.68)])
		b.lathe(off, prof, sides, K.CAP, 1.0)


static func _ribbons(b: PlantMeshBuilder, sp: PlantSpecies, lod: int, rng: RandomNumberGenerator) -> void:
	var h := sp.height
	var kelp := sp.form == &"kelp"
	var n: int = ([4, 3, 2] if kelp else [7, 4, 3])[lod]
	var segs: int = ([6, 4, 3] if kelp else [3, 2, 2])[lod]
	for k in n:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * h * rng.randf_range(0.0, 0.15)
		var bh := h * rng.randf_range(0.6, 1.0)
		var w := (0.12 if kelp else 0.05) * rng.randf_range(0.8, 1.2) * (1.0 + 0.3 * float(lod))
		var side := Vector3(-sin(a), 0, cos(a)) * w
		var pts := PackedVector3Array()
		var hw := PackedVector3Array()
		var phase := rng.randf() * TAU
		for j in segs + 1:
			var t := float(j) / float(segs)
			var wob := Vector3(cos(a), 0, sin(a)) * sin(t * 5.0 + phase) * bh * 0.06
			pts.append(base + Vector3(0, bh * t, 0) + wob)
			hw.append(side * (0.5 + 0.5 * sin(PI * clampf(t * 0.9 + 0.1, 0.0, 1.0))))
		b.strip(pts, hw, K.RIBBON, Vector3(cos(a), 0.3, sin(a)), 0.5, 1.0, rng.randf())


# --- Helpers ---------------------------------------------------------------------------

## Even directions on a sphere (Fibonacci) with a little jitter.
static func _fib_dir(k: int, n: int, rng: RandomNumberGenerator) -> Vector3:
	var y := 1.0 - (float(k) + 0.5) / float(n) * 2.0
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var a := float(k) * 2.39996 + rng.randf_range(-0.3, 0.3)
	return Vector3(cos(a) * r, y, sin(a) * r).normalized()


## Leaf cluster card at p facing roughly outward; normals point away from the crown centre.
static func _leaf_card(b: PlantMeshBuilder, p: Vector3, dir: Vector3, s: float, center: Vector3, radii: Vector3, kind: int, rng: RandomNumberGenerator) -> void:
	var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	var facing := (dir * 0.7 + rnd * 0.6).normalized()
	var right := facing.cross(Vector3.UP if absf(facing.y) < 0.95 else Vector3.RIGHT).normalized()
	right = right.rotated(facing, rng.randf_range(-0.6, 0.6))
	var up := right.cross(facing).normalized()
	var rel := p - center
	var nrm := Vector3(rel.x / maxf(radii.x, 0.01), rel.y / maxf(radii.y, 0.01), rel.z / maxf(radii.z, 0.01))
	nrm = (nrm.normalized() + Vector3.UP * 0.35).normalized()
	var ao := clampf(0.5 + 0.35 * (rel.y / maxf(radii.y, 0.01)) + 0.25 * rel.length() / maxf(radii.x, 0.01), 0.35, 1.0)
	b.card_centered(p, right * s, up * s, kind, nrm, ao, rng.randf())
