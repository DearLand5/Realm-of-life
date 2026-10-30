class_name RiverTracer
extends RefCounted
## Traces rivers from wet highlands down the drainage tree computed by
## Hydrology, joins tributaries, continues through lakes via their outlets,
## carves channels into the terrain and writes water=RIVER cells and
## `world.rivers` polylines with non-increasing water surface.

const MIN_CELLS := 14

var world: WorldData
var hydro: Hydrology
var _river_of := PackedInt32Array()   # river index per path cell (-1 none)
var _point_of := PackedInt32Array()   # point index within that river
var _paths: Array = []                # Array[PackedInt32Array] cell indices
var _surf: Array = []                 # Array[PackedFloat32Array] water surface per point
var _width: Array = []                # Array[PackedFloat32Array] width per point
var _lake_outflow := {}               # lake id -> true once its outlet river exists


func _init(w: WorldData, h: Hydrology) -> void:
	world = w
	hydro = h


func run(c: Dictionary, moisture: PackedFloat32Array, rng: Rng) -> void:
	var w := world
	var n := w.res * w.res
	_river_of.resize(n)
	_river_of.fill(-1)
	_point_of.resize(n)
	var count: int = c["rivers"]
	var width_mult: float = c["river_width"]
	if count <= 0:
		return
	var sources := _pick_sources(moisture, rng, 100000)
	var min_sep := w.size * 0.11
	var used: Array[Vector2] = []
	var made := 0
	for src in sources:
		if made >= count:
			break
		var p2 := Vector2(w.grid_to_world(src % w.res, src / w.res).x, w.grid_to_world(src % w.res, src / w.res).z)
		var close := false
		for u in used:
			if u.distance_to(p2) < min_sep:
				close = true
				break
		if close or _river_of[src] != -1:
			continue
		if _trace(src, w.heights[src] - 0.1, width_mult, 0.0):
			used.append(p2)
			made += 1
	_carve_all()
	_emit_polylines()


## Candidate sources sorted by score (wet, high, not too steep).
func _pick_sources(moisture: PackedFloat32Array, rng: Rng, max_count: int) -> PackedInt32Array:
	var w := world
	var res := w.res
	var top := w.sea_level
	for i in res * res:
		if w.water[i] == WorldData.Water.LAND:
			top = maxf(top, w.heights[i])
	var land_h := maxf(top - w.sea_level, 1.0)
	var cand: Array[Vector2] = []
	var step := maxi(2, res / 96)
	var margin := res / 12
	for iz in range(margin, res - margin, step):
		for ix in range(margin, res - margin, step):
			var i := iz * res + ix
			if w.water[i] != WorldData.Water.LAND:
				continue
			var rel := (w.heights[i] - w.sea_level) / land_h
			if rel < 0.22 or rel > 0.9 or moisture[i] < 0.3:
				continue
			var score := moisture[i] * pow(rel, 0.6) * rng.range_f(0.55, 1.0)
			cand.append(Vector2(-score, float(i)))
	cand.sort()
	var out := PackedInt32Array()
	for k in mini(cand.size(), max_count):
		out.append(int(cand[k].y))
	return out


## Follows the drainage tree from `src`. Returns false if the path is too short.
func _trace(src: int, start_level: float, width_mult: float, start_dist: float, start_width: float = 0.0) -> bool:
	var w := world
	var path := PackedInt32Array([src])
	var c := src
	var end_lake := -1
	var join_river := -1
	var join_point := -1
	var guard := w.res * w.res
	while guard > 0:
		guard -= 1
		var p := hydro.parent[c]
		if p < 0:
			break
		path.append(p)
		if w.water[p] == WorldData.Water.OCEAN:
			break
		if hydro.lake_id[p] >= 0 and hydro.lake_id[p] != hydro.lake_id[src]:
			end_lake = hydro.lake_id[p]
			break
		if _river_of[p] >= 0:
			join_river = _river_of[p]
			join_point = _point_of[p]
			break
		c = p
	if path.size() < MIN_CELLS and start_width <= 0.0:
		return false
	var idx := _paths.size()
	var surf := PackedFloat32Array()
	var wid := PackedFloat32Array()
	surf.resize(path.size())
	wid.resize(path.size())
	var level := start_level
	var dist := start_dist
	for k in path.size():
		var cell := path[k]
		if k > 0:
			var a := w.grid_to_world(path[k - 1] % w.res, path[k - 1] / w.res)
			var b := w.grid_to_world(cell % w.res, cell / w.res)
			dist += Vector2(a.x - b.x, a.z - b.z).length()
		var ground := w.heights[cell]
		if w.water[cell] == WorldData.Water.OCEAN:
			ground = w.sea_level + 0.1
		elif w.water[cell] == WorldData.Water.LAKE:
			ground = w.water_surface[cell] + 0.1
		level = minf(level, ground - 0.12)
		surf[k] = level
		var base := width_mult * (2.0 + 3.0 * sqrt(dist / 300.0))
		wid[k] = maxf(base, start_width)
		if _river_of[cell] == -1:
			_river_of[cell] = idx
			_point_of[cell] = k
	if join_river >= 0:
		# Tributary joins: its end takes the main river's level; main widens below.
		surf[path.size() - 1] = minf(level, (_surf[join_river] as PackedFloat32Array)[join_point])
		var mw: PackedFloat32Array = _width[join_river]
		var tw := wid[path.size() - 1]
		for k in range(join_point, mw.size()):
			mw[k] = sqrt(mw[k] * mw[k] + tw * tw * 0.6)
	_paths.append(path)
	_surf.append(surf)
	_width.append(wid)
	if end_lake >= 0 and not _lake_outflow.has(end_lake):
		_lake_outflow[end_lake] = true
		var lake: Dictionary = hydro.lakes[end_lake]
		var outlet: int = lake["outlet"]
		_trace(outlet, float(lake["level"]) - 0.02, width_mult, dist, wid[path.size() - 1])
	return true


## Lowers terrain along every river and marks river cells.
func _carve_all() -> void:
	var w := world
	var res := w.res
	var best_r := PackedFloat32Array()
	best_r.resize(res * res)
	best_r.fill(INF)
	for r in _paths.size():
		var pts := _smoothed(r)
		var surf: PackedFloat32Array = _surf[r]
		var wid: PackedFloat32Array = _width[r]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var steps := maxi(1, int(ceil(a.distance_to(b) / (w.cell * 0.5))))
			for s in steps:
				var t := float(s) / float(steps)
				var p := a.lerp(b, t)
				_stamp(p, lerpf(surf[k], surf[k + 1], t), lerpf(wid[k], wid[k + 1], t), best_r)
		var last: Vector2 = pts[pts.size() - 1]
		_stamp(last, surf[surf.size() - 1], wid[wid.size() - 1], best_r)


func _stamp(p: Vector2, level: float, width: float, best_r: PackedFloat32Array) -> void:
	var w := world
	var res := w.res
	var half_w := width * 0.5
	var bank := maxf(2.5 * w.cell, width * 0.7)
	var depth := 0.45 + 0.28 * width
	var reach := half_w + bank
	var g := w.world_to_grid(p.x, p.y)
	var r_cells := int(ceil(reach / w.cell))
	var gx := int(round(g.x))
	var gz := int(round(g.y))
	for dz in range(-r_cells, r_cells + 1):
		var iz := gz + dz
		if iz < 0 or iz >= res:
			continue
		for dx in range(-r_cells, r_cells + 1):
			var ix := gx + dx
			if ix < 0 or ix >= res:
				continue
			var i := iz * res + ix
			var wt := w.water[i]
			if wt == WorldData.Water.OCEAN or wt == WorldData.Water.LAKE:
				continue
			var wx := -w.size * 0.5 + float(ix) * w.cell
			var wz := -w.size * 0.5 + float(iz) * w.cell
			var r := Vector2(wx - p.x, wz - p.y).length()
			if r > reach:
				continue
			var target: float
			if r < half_w:
				var q := r / half_w
				target = level - depth * (1.0 - q * q)
			else:
				var q2 := (r - half_w) / bank
				target = level + q2 * q2 * (3.0 - 2.0 * q2) * 1.2 + 0.05
			if w.heights[i] > target:
				w.heights[i] = target
			if r < half_w + w.cell * 0.35 and w.heights[i] < level and r < best_r[i]:
				best_r[i] = r
				w.water[i] = WorldData.Water.RIVER
				w.water_surface[i] = level


## Path cells -> world xz, lightly smoothed (keeps both ends).
func _smoothed(r: int) -> Array[Vector2]:
	var w := world
	var path: PackedInt32Array = _paths[r]
	var raw: Array[Vector2] = []
	for cell in path:
		var p := w.grid_to_world(cell % w.res, cell / w.res)
		raw.append(Vector2(p.x, p.z))
	var out: Array[Vector2] = []
	var n := raw.size()
	for k in n:
		if k == 0 or k == n - 1:
			out.append(raw[k])
			continue
		var acc := Vector2.ZERO
		var cnt := 0
		for j in range(maxi(0, k - 2), mini(n, k + 3)):
			acc += raw[j]
			cnt += 1
		out.append(acc / float(cnt))
	return out


func _emit_polylines() -> void:
	world.rivers.clear()
	for r in _paths.size():
		var pts := _smoothed(r)
		var surf: PackedFloat32Array = _surf[r]
		var wid: PackedFloat32Array = _width[r]
		var line := PackedVector3Array()
		var widths := PackedFloat32Array()
		for k in pts.size():
			line.append(Vector3(pts[k].x, surf[k], pts[k].y))
			widths.append(wid[k])
		world.rivers.append({"points": line, "widths": widths})
