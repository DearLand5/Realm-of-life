class_name FloraPlacement
extends RefCounted
## Stable, deterministic plant instance placement inside an eco cell.
## Instance k of (cell, species) always lands on the same spot, so changing
## the instance count only adds/removes instances at the end of the list.
## Spots are stratified on an 8×8 sub-grid (permuted per species) so plants
## spread evenly and species interleave instead of piling up.

const SUB := 8
const SLOTS := SUB * SUB


## Offset inside the cell in metres (x, z) plus two random values in z/w.
static func spot(cx: int, cz: int, plant: int, k: int, cell_size: float) -> Vector4:
	var b := int(Rng.hash01(cx * 31 + 7, cz * 17 + 3, plant * 977 + 11) * float(SLOTS))
	var a := 37 + 2 * (plant % 5)   # odd multiplier → permutation of the 64 slots
	var slot := (a * k + b) % SLOTS
	var cycle := k / SLOTS
	var jx := Rng.hash01(cx * 131 + k, cz * 71 + plant, cycle * 7 + 1)
	var jz := Rng.hash01(cz * 113 + k, cx * 59 + plant, cycle * 7 + 2)
	var r1 := Rng.hash01(cx + k * 7, cz - plant * 13, cycle * 7 + 3)
	var r2 := Rng.hash01(cz + k * 11, cx + plant * 19, cycle * 7 + 4)
	var fx := (float(slot % SUB) + jx) / float(SUB)
	var fz := (float(slot / SUB) + jz) / float(SUB)
	return Vector4(fx * cell_size, fz * cell_size, r1, r2)


## Instance count for a biomass (kg/m²) with a stable per-cell dither.
static func count_for(biomass: float, cell_size: float, per_instance: float, density: float, cx: int, cz: int, plant: int) -> int:
	if biomass <= 0.0 or per_instance <= 0.0:
		return 0
	var n := biomass * cell_size * cell_size / per_instance * density
	return int(floor(n + Rng.hash01(cx * 3 + 1, cz * 5 + 2, plant * 7 + 3)))
