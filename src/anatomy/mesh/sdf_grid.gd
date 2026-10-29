class_name SdfGrid
extends RefCounted
## Uniform sampling grid fitted to an SdfField, split into cubic bricks of
## BRICK³ cells. Each brick keeps the list of primitives whose bounds overlap
## it, so field queries inside a brick touch only nearby primitives.

const BRICK := 4

var field: SdfField
var origin := Vector3.ZERO
var cell: float = 0.01
var cells := Vector3i.ONE      # cell counts (multiples of BRICK)
var points := Vector3i.ONE     # grid point counts = cells + 1
var bricks := Vector3i.ONE     # brick counts
var brick_cand: Array[PackedInt32Array] = []
var _empty := PackedInt32Array()


## `bounds` is the region to sample, `target_cells` the number of cells along
## its largest extent; `margin` extra cells are added on every side.
static func create(f: SdfField, bounds: AABB, target_cells: int, margin: int = 2) -> SdfGrid:
	var g := SdfGrid.new()
	g.field = f
	var ext := bounds.size
	var max_e := maxf(ext.x, maxf(ext.y, ext.z))
	if max_e <= 0.0 or not is_finite(max_e):
		max_e = 0.01
	g.cell = max_e / float(maxi(target_cells, 4))
	var raw := Vector3i(ceili(ext.x / g.cell), ceili(ext.y / g.cell), ceili(ext.z / g.cell)) + Vector3i.ONE * margin * 2
	g.bricks = Vector3i(ceili(raw.x / float(BRICK)), ceili(raw.y / float(BRICK)), ceili(raw.z / float(BRICK)))
	g.cells = g.bricks * BRICK
	g.points = g.cells + Vector3i.ONE
	g.origin = bounds.get_center() - Vector3(g.cells) * g.cell * 0.5
	g._assign_candidates()
	return g


func _assign_candidates() -> void:
	var nb := bricks.x * bricks.y * bricks.z
	brick_cand.resize(nb)
	for i in nb:
		brick_cand[i] = PackedInt32Array()
	var bs := cell * float(BRICK)
	for j in field.count:
		var bb: AABB = field.box[j]
		var lo := ((bb.position - origin) / bs).floor()
		var hi := ((bb.end - origin) / bs).floor()
		var x0 := clampi(int(lo.x), 0, bricks.x - 1)
		var y0 := clampi(int(lo.y), 0, bricks.y - 1)
		var z0 := clampi(int(lo.z), 0, bricks.z - 1)
		var x1 := clampi(int(hi.x), 0, bricks.x - 1)
		var y1 := clampi(int(hi.y), 0, bricks.y - 1)
		var z1 := clampi(int(hi.z), 0, bricks.z - 1)
		for bz in range(z0, z1 + 1):
			for by in range(y0, y1 + 1):
				for bx in range(x0, x1 + 1):
					var bi := bx + bricks.x * (by + bricks.y * bz)
					var arr := brick_cand[bi]
					arr.append(j)
					brick_cand[bi] = arr


func brick_index(bx: int, by: int, bz: int) -> int:
	return bx + bricks.x * (by + bricks.y * bz)


## Candidate primitives for any point (clamped to the grid).
func cand_at(p: Vector3) -> PackedInt32Array:
	var q := (p - origin) / (cell * float(BRICK))
	var bx := int(floorf(q.x))
	var by := int(floorf(q.y))
	var bz := int(floorf(q.z))
	if bx < 0 or by < 0 or bz < 0 or bx >= bricks.x or by >= bricks.y or bz >= bricks.z:
		return _empty
	return brick_cand[bx + bricks.x * (by + bricks.y * bz)]


func point_pos(x: int, y: int, z: int) -> Vector3:
	return origin + Vector3(x, y, z) * cell
