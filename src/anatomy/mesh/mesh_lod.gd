class_name MeshLod
extends RefCounted
## Level-of-detail settings for creature meshes (0 = closest).
##   LOD0  editor / close-up      ~64 SDF cells along the largest extent
##   LOD1  tier A in the world    ~34 cells
##   LOD2  tier B / far           ~18 cells, silhouette-level accessories

const COUNT := 3
const CELLS: Array[int] = [64, 34, 18]
## SDF chains thinner than this many cells are rendered as tubes at that LOD.
const THIN_CELLS: Array[float] = [0.75, 0.8, 0.85]
const NEWTON: Array[int] = [2, 2, 1]
const SMOOTH: Array[int] = [1, 0, 0]
const AO: Array[bool] = [true, true, false]
const TUBE_SIDES: Array[int] = [10, 7, 4]
const RINGS_PER_BONE: Array[int] = [5, 3, 1]
## Accessory detail: 2 = everything, 1 = main features, 0 = silhouette only.
const DETAIL: Array[int] = [2, 1, 0]
const SPHERE_AROUND: Array[int] = [18, 10, 6]
const SPHERE_UP: Array[int] = [12, 7, 4]


static func clamp_lod(lod: int) -> int:
	return clampi(lod, 0, COUNT - 1)


static func cells(lod: int) -> int:
	return CELLS[clamp_lod(lod)]


static func tube_sides(lod: int, radius_cells: float = 10.0) -> int:
	var s := TUBE_SIDES[clamp_lod(lod)]
	# Very thin tubes need fewer sides (they cover a few pixels).
	if radius_cells < 0.35:
		s = mini(s, 5)
	return maxi(s, 3)


static func rings_per_bone(lod: int) -> int:
	return RINGS_PER_BONE[clamp_lod(lod)]


static func detail(lod: int) -> int:
	return DETAIL[clamp_lod(lod)]


## Scales a segment count for the LOD (at least `min_v`).
static func seg(lod: int, lod0_count: int, min_v: int = 3) -> int:
	var f: float = [1.0, 0.6, 0.35][clamp_lod(lod)]
	return maxi(min_v, int(round(float(lod0_count) * f)))
