class_name SpatialHash
extends RefCounted
## Uniform-grid spatial index on the XZ plane for neighbour queries
## (perception, collisions, flocking). Objects are any Variant ids/objects with
## a position supplied by the caller. O(1) insert/move/remove.

var cell_size: float = 8.0
var _cells: Dictionary = {}     # Vector2i -> Array
var _where: Dictionary = {}     # object -> Vector2i
var _pos: Dictionary = {}       # object -> Vector3


func _init(cell: float = 8.0) -> void:
	cell_size = cell


func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / cell_size)), int(floor(p.z / cell_size)))


func insert(obj, p: Vector3) -> void:
	if _where.has(obj):
		move(obj, p)
		return
	var k := _key(p)
	if not _cells.has(k):
		_cells[k] = []
	(_cells[k] as Array).append(obj)
	_where[obj] = k
	_pos[obj] = p


func move(obj, p: Vector3) -> void:
	if not _where.has(obj):
		insert(obj, p)
		return
	_pos[obj] = p
	var k := _key(p)
	var old: Vector2i = _where[obj]
	if k == old:
		return
	var arr: Array = _cells.get(old, [])
	arr.erase(obj)
	if arr.is_empty():
		_cells.erase(old)
	if not _cells.has(k):
		_cells[k] = []
	(_cells[k] as Array).append(obj)
	_where[obj] = k


func remove(obj) -> void:
	if not _where.has(obj):
		return
	var k: Vector2i = _where[obj]
	var arr: Array = _cells.get(k, [])
	arr.erase(obj)
	if arr.is_empty():
		_cells.erase(k)
	_where.erase(obj)
	_pos.erase(obj)


func has(obj) -> bool:
	return _where.has(obj)


func position_of(obj) -> Vector3:
	return _pos.get(obj, Vector3.INF)


func size() -> int:
	return _where.size()


func clear() -> void:
	_cells.clear()
	_where.clear()
	_pos.clear()


## Objects within `radius` (XZ distance) of p, excluding `exclude`.
func query(p: Vector3, radius: float, exclude = null, max_results: int = 64) -> Array:
	var out := []
	var r2 := radius * radius
	var k0 := _key(p - Vector3(radius, 0, radius))
	var k1 := _key(p + Vector3(radius, 0, radius))
	for cz in range(k0.y, k1.y + 1):
		for cx in range(k0.x, k1.x + 1):
			var arr = _cells.get(Vector2i(cx, cz))
			if arr == null:
				continue
			for obj in arr:
				if obj == exclude:
					continue
				var q: Vector3 = _pos[obj]
				var dx := q.x - p.x
				var dz := q.z - p.z
				if dx * dx + dz * dz <= r2:
					out.append(obj)
					if out.size() >= max_results:
						return out
	return out


## Nearest object within radius satisfying `filter` (Callable(obj) -> bool).
func nearest(p: Vector3, radius: float, filter: Callable = Callable(), exclude = null):
	var best = null
	var best_d := INF
	for obj in query(p, radius, exclude, 256):
		if filter.is_valid() and not filter.call(obj):
			continue
		var d := (_pos[obj] as Vector3).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = obj
	return best
