class_name StaticBiomass
extends RefCounted
## Equilibrium plant biomass (kg/m²) from climate suitability, used until the
## ecosystem simulation supplies live values. Per eco cell and species:
## capacity × suitability × competition share within its layer × biome
## vegetation × world "vegetation" setting × fertility, with canopy shading
## the ground layers and noise clearings in forests.

const LAYER := {
	&"broadleaf_tree": 0, &"conifer": 0, &"palm": 0,
	&"shrub": 1, &"cactus": 1, &"fern": 1, &"reed": 1,
	&"grass": 2, &"flower": 2, &"mushroom": 2,
	&"kelp": 3, &"algae": 3,
}

var dim: int = 0
var cell_size: float = 8.0
var _grid: Array[PackedFloat32Array] = []


func _init(world: WorldData, species: Array[PlantSpecies], cs: float = 8.0) -> void:
	cell_size = maxf(cs, 1.0)
	dim = int(ceil(world.size / cell_size))
	var n_sp := species.size()
	for p in n_sp:
		var g := PackedFloat32Array()
		g.resize(dim * dim)
		_grid.append(g)
	var vmult := clampf(float(world.config.get("vegetation", 1.0)), 0.0, 2.0)
	var noise := FastNoiseLite.new()
	noise.seed = int(world.config.get("seed", 1)) + 501
	noise.frequency = 1.0 / 45.0
	noise.fractal_octaves = 2
	var half := world.size * 0.5
	var suit := PackedFloat32Array()
	suit.resize(n_sp)
	for cz in dim:
		for cx in dim:
			var x := -half + (float(cx) + 0.5) * cell_size
			var z := -half + (float(cz) + 0.5) * cell_size
			if not world.contains(x, z):
				continue
			var b := world.biome_at(x, z)
			var depth := world.water_depth_at(x, z)
			var in_water := depth > 0.3
			var temp := world.base_temperature_at(x, z)
			var moist := world.moisture_at(x, z)
			var fert := world.fertility_at(x, z)
			var slope := world.slope_at(x, z)
			var shore := world.water_distance_at(x, z)
			var veg := Biomes.vegetation(b) * vmult * (0.55 + 0.7 * fert)
			# Suitability and per-layer competition (squared shares favour the dominant species).
			var sq := [0.0, 0.0, 0.0, 0.0]
			for p in n_sp:
				var sp := species[p]
				var s := sp.suitability(temp, moist, in_water)
				if sp.form == &"reed":
					s *= 1.0 if (shore < 7.0 or b == Biomes.SWAMP) and depth < 0.5 else 0.05
				elif sp.aquatic:
					s *= smoothstep(0.3, 1.0, depth) * (1.0 - smoothstep(12.0, 18.0, depth))
					if sp.form == &"algae":
						s *= 1.0 - smoothstep(3.0, 6.0, depth)
				elif LAYER.get(sp.form, 2) == 0:
					s *= 1.0 - smoothstep(0.6, 1.1, slope)
				suit[p] = s
				var layer: int = LAYER.get(sp.form, 2)
				sq[layer] = float(sq[layer]) + s * s
			var clearing := smoothstep(-0.35, 0.15, noise.get_noise_2d(x, z))
			var cover := 0.0
			for p in n_sp:
				var sp := species[p]
				var layer: int = LAYER.get(sp.form, 2)
				if layer != 0:
					continue
				var s := suit[p]
				var share := s * s / (float(sq[0]) + 0.02)
				var bm := sp.capacity * s * share * veg * clearing
				_grid[p][cz * dim + cx] = bm
				cover += bm / maxf(sp.capacity, 0.01)
			cover = clampf(cover, 0.0, 1.0)
			for p in n_sp:
				var sp := species[p]
				var layer: int = LAYER.get(sp.form, 2)
				if layer == 0:
					continue
				var s := suit[p]
				var share := s * s / (float(sq[layer]) + 0.02)
				var shade := 1.0
				if layer == 1:
					shade = 1.0 - 0.35 * cover
				elif layer == 2:
					shade = 1.0 - 0.55 * cover
				var bm := sp.capacity * s * share * veg * shade
				if sp.form == &"mushroom":
					bm *= cover
				elif sp.form == &"flower":
					bm *= 0.4 + 0.6 * (1.0 - clearing)
				_grid[p][cz * dim + cx] = bm


## kg/m² of plant `p` in eco cell (cx, cz); 0 outside the grid.
func sample(cx: int, cz: int, p: int) -> float:
	if p < 0 or p >= _grid.size() or cx < 0 or cz < 0 or cx >= dim or cz >= dim:
		return 0.0
	return _grid[p][cz * dim + cx]


func set_value(cx: int, cz: int, p: int, kg_m2: float) -> void:
	if p < 0 or p >= _grid.size() or cx < 0 or cz < 0 or cx >= dim or cz >= dim:
		return
	_grid[p][cz * dim + cx] = maxf(0.0, kg_m2)
