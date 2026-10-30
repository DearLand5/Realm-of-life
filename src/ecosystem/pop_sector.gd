class_name PopSector
extends RefCounted
## A square region (default 32 m) holding the population pools of tiers C/D
## plus cached static geography and the per-step environment.

enum Tier { A = 0, B = 1, C = 2, D = 3 }

var index: int = 0
var sx: int = 0
var sz: int = 0
var x0: float = 0.0
var z0: float = 0.0
var x1: float = 0.0
var z1: float = 0.0
var center := Vector3.ZERO
var cells := PackedInt32Array()        # EcoGrid cells inside
var water_cells := PackedInt32Array()
var area: float = 1024.0
var land_frac: float = 1.0
var water_frac: float = 0.0
var fresh_water := false              # drinkable water (lake/river) inside
var base_temp: float = 15.0
var base_temp_water: float = 15.0
var base_moist: float = 0.5
var pools: Dictionary = {}            # species_id -> SpeciesPool
var tier: int = Tier.C
var pending_dt: float = 0.0           # accumulated time of rarely stepped (D) sectors

# Environment of the current step (daily means; written by PopulationManager).
var t_air: float = 15.0
var t_water: float = 15.0
var humidity: float = 0.5
var light: float = 0.5
var oxygen_water: float = 0.8


func total_count() -> float:
	var t := 0.0
	for p in pools.values():
		t += (p as SpeciesPool).count
	return t
