class_name CreatureMeshBuilder
extends RefCounted
## AnatomyModel + LOD -> CreatureMeshData (pure function, thread-safe).
##
##  1. Chains thinner than MeshLod.THIN_CELLS grid cells leave the SDF and
##     become tubes at this LOD (prevents broken sub-cell limbs).
##  2. Surface Nets body (SdfMesher) + skin weights / attributes (BodySkinning).
##  3. Tubes for thin chains (compiler "tube" accessories + LOD tubes).
##  4. Procedural accessories by type (AccessoryBuilder), one buffer per
##     material kind.

const HARD_COVERINGS: Array[StringName] = [&"chitin", &"plates", &"shell", &"scales"]


static func cache_key(model: AnatomyModel, lod: int) -> String:
	var k := model.morph_key if model != null else ""
	if k == "" and model != null:
		k = "anon_%d" % _geometry_hash(model)
	return "%s#%d" % [k, MeshLod.clamp_lod(lod)]


static func build_data(model: AnatomyModel, lod: int) -> CreatureMeshData:
	var data := CreatureMeshData.new()
	data.lod = MeshLod.clamp_lod(lod)
	if model == null or model.bones.is_empty():
		data.key = "null#%d" % data.lod
		data.bind_poses.append(Transform3D.IDENTITY)
		return data
	data.key = cache_key(model, lod)
	data.bind_poses = SkeletonBuilder.bind_poses(model)
	var t0 := Time.get_ticks_usec()
	var rig := CreatureRig.new(model)
	var ctx := CreatureBuildContext.new(model, rig, data.lod)
	var cells := MeshLod.cells(data.lod)

	# 1. LOD tubes.
	var full := SdfField.from_model(model)
	var exclude := {}
	var lod_tubes: Array[PackedInt32Array] = []
	if not full.is_empty():
		var cell_est := _max_extent(full.bounds()) / float(cells)
		_collect_lod_tubes(model, cell_est * MeshLod.THIN_CELLS[data.lod], exclude, lod_tubes)
	var field := full if exclude.is_empty() else SdfField.from_model(model, exclude)
	ctx.field = field

	# 2. SDF body.
	var mstats := {}
	var t1 := Time.get_ticks_usec()
	if not field.is_empty():
		var grid := SdfGrid.create(field, field.bounds(), cells)
		ctx.grid = grid
		ctx.cell = grid.cell
		ctx.kernel = BodySkinning.Kernel.new(rig, grid)
		var res := SdfMesher.polygonize(grid, MeshLod.NEWTON[data.lod], MeshLod.SMOOTH[data.lod])
		mstats = res.stats
		ctx.buffers[CreatureBuildContext.KIND_BODY] = BodySkinning.build(rig, grid, res, MeshLod.AO[data.lod])
	else:
		ctx.cell = maxf(_max_extent(model.aabb), 0.01) / float(cells)
	var t2 := Time.get_ticks_usec()

	# 3. Tubes.
	var body := ctx.buffer(CreatureBuildContext.KIND_BODY)
	for a in model.accessories:
		if a.type != &"tube":
			continue
		var chain := _bones_param(a.params.get("bones"))
		if chain.is_empty():
			continue
		var hard := HARD_COVERINGS.has(ctx.covering_type(model.bones[chain[0]].covering))
		TubeBuilder.chain_tube(ctx, body, chain, 0.08 if hard else 0.3)
	for chain in lod_tubes:
		var root_flare := 0.3 if model.bones[chain[0]].instance != model.bones[maxi(model.bones[chain[0]].parent, 0)].instance else 0.0
		TubeBuilder.chain_tube(ctx, body, chain, root_flare)
	var t3 := Time.get_ticks_usec()

	# 4. Accessories.
	AccessoryBuilder.build_all(ctx)
	var t4 := Time.get_ticks_usec()

	var repaired := 0
	for k in ctx.buffers:
		repaired += (ctx.buffers[k] as MeshBuffer).sanitize()
	data.buffers = ctx.buffers
	data.stats = {
		"lod": data.lod, "cells": cells, "cell": ctx.cell, "lod_tubes": lod_tubes.size(),
		"body_vertices": body.vertex_count(), "vertices": data.vertex_count(),
		"t_prepare_ms": (t1 - t0) / 1000.0, "t_body_ms": (t2 - t1) / 1000.0,
		"t_tubes_ms": (t3 - t2) / 1000.0, "t_accessories_ms": (t4 - t3) / 1000.0,
		"t_total_ms": (t4 - t0) / 1000.0, "mesher": mstats, "repaired": repaired,
		"warnings": ctx.warnings,
	}
	return data


## Chains (part instances) whose radius drops below `thr`: from the first thin
## bone to the chain tip they are excluded from the SDF and rendered as tubes.
## The root instance always stays in the SDF.
static func _collect_lod_tubes(m: AnatomyModel, thr: float, exclude: Dictionary, out: Array[PackedInt32Array]) -> void:
	for ii in m.instances.size():
		if ii == 0:
			continue
		var inst := m.instances[ii]
		var chain := PackedInt32Array()
		var started := false
		for bi in inst.bones:
			var b := m.bones[bi]
			if b.thin:
				break
			if not started and minf(b.r0, b.r1) * minf(1.0, b.flatten) < thr:
				started = true
			if started:
				chain.append(bi)
				exclude[bi] = true
		if not chain.is_empty():
			out.append(chain)


static func _bones_param(v) -> PackedInt32Array:
	if v is PackedInt32Array:
		return v
	var out := PackedInt32Array()
	if v is Array:
		for x in v:
			out.append(int(x))
	return out


static func _max_extent(bb: AABB) -> float:
	return maxf(bb.size.x, maxf(bb.size.y, bb.size.z))


static func _geometry_hash(m: AnatomyModel) -> int:
	var parts := PackedStringArray()
	for b in m.bones:
		parts.append("%.4f,%.4f,%.4f,%.4f,%.4f" % [b.start.x, b.start.y, b.start.z, b.r0, b.r1])
	for a in m.accessories:
		parts.append("%s%.4f" % [a.type, a.size])
	return MathUtil.fnv1a(",".join(parts))
