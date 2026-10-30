extends SceneTree
func _initialize() -> void:
	await process_frame
	var ids := OS.get_cmdline_user_args()
	for id in ids:
		var ph := Phenotype.build(BodyPlanPresets.create(StringName(id)))
		var m := ph.anatomy
		print("=== %s bones=%d aabb=%s axis=%s support_tips=%s" % [id, m.bones.size(), m.aabb, m.body_axis, str(m.stats.get("support_tips"))])
		for b in m.bones:
			print("  #%d %-16s par=%d kind=%s fn=%s inst=%d seg=%d side=%d tip=%s len=%.3f s=(%.2f,%.2f,%.2f) e=(%.2f,%.2f,%.2f)" % [b.index, b.name, b.parent, b.kind, b.function, b.instance, b.segment, b.side, b.is_tip, b.length, b.start.x, b.start.y, b.start.z, b.end.x, b.end.y, b.end.z])
		for i in m.instances.size():
			var inst := m.instances[i]
			print("  inst %d part=%d kind=%s mirrored=%s side=%d bones=%s" % [i, inst.part_id, inst.kind, inst.mirrored, inst.side, str(inst.bones)])
	quit()
