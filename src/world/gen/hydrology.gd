class_name Hydrology
extends RefCounted
## Water on a generated height field:
##   1. ocean = cells below sea level connected to the map border;
##   2. priority-flood (monotone bucket queue) from the ocean gives every land
##      cell its spill level and a downstream neighbour (drainage tree);
##   3. depressions (spill > ground) become lakes when large/deep enough,
##      smaller ones are partly silted up;
##   4. rivers are traced down the drainage tree (see RiverTracer).

const DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const DZ: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const QUANT := 0.02          # bucket size of the priority queue, metres

var world: WorldData
var spill := PackedFloat32Array()   # flood level (ground where no depression)
var parent := PackedInt32Array()    # downstream cell, -1 at outlets / ocean
var order := PackedInt32Array()     # land cells in flood order (outlets first)
var lake_id := PackedInt32Array()   # kept lake index per cell, -1 otherwise
## [{level: float, outlet: int, cells: int, max_depth: float}]
var lakes: Array = []


func _init(w: WorldData) -> void:
	world = w


func run(c: Dictionary) -> void:
	_mark_ocean()
	_flood()
	_find_lakes(float(c.get("lakes", 0.6)))


func _mark_ocean() -> void:
	var w := world
	var res := w.res
	var n := res * res
	var sea := w.sea_level
	for i in n:
		w.water[i] = WorldData.Water.LAND
		w.water_surface[i] = sea
	var queue := PackedInt32Array()
	queue.resize(n)
	var qh := 0
	var qt := 0
	for k in res:
		for i in [k, (res - 1) * res + k, k * res, k * res + res - 1]:
			if w.heights[i] < sea and w.water[i] == WorldData.Water.LAND:
				w.water[i] = WorldData.Water.OCEAN
				queue[qt] = i
				qt += 1
	while qh < qt:
		var c := queue[qh]
		qh += 1
		var cx := c % res
		var cz := c / res
		for k in 4:
			var nx := cx + DX[k]
			var nz := cz + DZ[k]
			if nx < 0 or nz < 0 or nx >= res or nz >= res:
				continue
			var j := nz * res + nx
			if w.water[j] == WorldData.Water.LAND and w.heights[j] < sea:
				w.water[j] = WorldData.Water.OCEAN
				queue[qt] = j
				qt += 1


func _flood() -> void:
	var w := world
	var res := w.res
	var n := res * res
	var h := w.heights
	spill.resize(n)
	parent.resize(n)
	order.resize(n)
	parent.fill(-1)
	var visited := PackedByteArray()
	visited.resize(n)
	var lo := w.sea_level
	var hi := lo
	for v in h:
		hi = maxf(hi, v)
		lo = minf(lo, v)
	var nb := int((hi - lo) / QUANT) + 4
	var head := PackedInt32Array()
	head.resize(nb)
	head.fill(-1)
	var tail := PackedInt32Array()
	tail.resize(nb)
	tail.fill(-1)
	var nxt := PackedInt32Array()
	nxt.resize(n)
	var count := 0
	var any_ocean := false
	for i in n:
		if w.water[i] == WorldData.Water.OCEAN:
			visited[i] = 1
			spill[i] = w.sea_level
			any_ocean = true
	# Seeds: ocean cells touching land (or the whole border on oceanless maps).
	for i in n:
		var seed_it := false
		var level := 0.0
		if any_ocean:
			if w.water[i] == WorldData.Water.OCEAN and _touches_land(i):
				seed_it = true
				level = w.sea_level
		else:
			var ix := i % res
			var iz := i / res
			if ix == 0 or iz == 0 or ix == res - 1 or iz == res - 1:
				seed_it = true
				level = h[i]
				visited[i] = 1
				spill[i] = level
		if seed_it:
			var b := int((level - lo) / QUANT)
			nxt[i] = -1
			if head[b] == -1:
				head[b] = i
			else:
				nxt[tail[b]] = i
			tail[b] = i
			count += 1
	var cur := 0
	var n_order := 0
	while count > 0:
		while head[cur] == -1:
			cur += 1
		var c := head[cur]
		head[cur] = nxt[c]
		count -= 1
		if w.water[c] != WorldData.Water.OCEAN:
			order[n_order] = c
			n_order += 1
		var sc := spill[c]
		var cx := c % res
		var cz := c / res
		for k in 8:
			var nx := cx + DX[k]
			var nz := cz + DZ[k]
			if nx < 0 or nz < 0 or nx >= res or nz >= res:
				continue
			var j := nz * res + nx
			if visited[j] != 0:
				continue
			visited[j] = 1
			var s := maxf(h[j], sc)
			spill[j] = s
			parent[j] = c
			var b := int((s - lo) / QUANT)
			nxt[j] = -1
			if head[b] == -1:
				head[b] = j
			else:
				nxt[tail[b]] = j
			tail[b] = j
			count += 1
	order.resize(n_order)


func _touches_land(i: int) -> bool:
	var res := world.res
	var ix := i % res
	var iz := i / res
	for k in 8:
		var nx := ix + DX[k]
		var nz := iz + DZ[k]
		if nx < 0 or nz < 0 or nx >= res or nz >= res:
			continue
		if world.water[nz * res + nx] != WorldData.Water.OCEAN:
			return true
	return false


func _find_lakes(lakes_param: float) -> void:
	var w := world
	var res := w.res
	var n := res * res
	var h := w.heights
	lake_id.resize(n)
	lake_id.fill(-1)
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var pos := PackedInt32Array()
	pos.resize(n)
	pos.fill(0x7FFFFFFF)
	for k in order.size():
		pos[order[k]] = k
	var min_area := lerpf(4000.0, 60.0, lakes_param)
	var min_depth := lerpf(5.0, 0.7, lakes_param)
	var cell_area := w.cell * w.cell
	var queue := PackedInt32Array()
	queue.resize(n)
	var n_comp := 0
	for i in n:
		if comp[i] != -1 or w.water[i] == WorldData.Water.OCEAN or spill[i] - h[i] <= 0.02:
			continue
		# Collect one flooded depression (4-connected).
		var qh := 0
		var qt := 1
		queue[0] = i
		comp[i] = n_comp
		var max_d := 0.0
		var level := spill[i]
		var outlet := i
		while qh < qt:
			var cc := queue[qh]
			qh += 1
			max_d = maxf(max_d, spill[cc] - h[cc])
			level = maxf(level, spill[cc])
			if pos[cc] < pos[outlet]:
				outlet = cc
			var cx := cc % res
			var cz := cc / res
			for k in 4:
				var nx := cx + DX[k]
				var nz := cz + DZ[k]
				if nx < 0 or nz < 0 or nx >= res or nz >= res:
					continue
				var j := nz * res + nx
				if comp[j] == -1 and w.water[j] != WorldData.Water.OCEAN and spill[j] - h[j] > 0.02:
					comp[j] = n_comp
					queue[qt] = j
					qt += 1
		var keep := lakes_param > 0.01 and float(qt) * cell_area >= min_area and max_d >= min_depth
		if keep:
			var id := lakes.size()
			lakes.append({"level": level, "outlet": outlet, "cells": qt, "max_depth": max_d})
			for q in qt:
				var cq := queue[q]
				lake_id[cq] = id
				w.water[cq] = WorldData.Water.LAKE
				w.water_surface[cq] = level
		else:
			# Silt up: keep only a shallow trace of the basin.
			for q in qt:
				var cq := queue[q]
				h[cq] = spill[cq] - (spill[cq] - h[cq]) * 0.3
		n_comp += 1
