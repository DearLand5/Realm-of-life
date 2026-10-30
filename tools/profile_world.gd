extends SceneTree
## Thin launcher: per-frame cost breakdown of the world scene (see profile_world_impl.gd).
##   tools/shot.sh tools/profile_world.gd

func _initialize() -> void:
	await process_frame
	var n: Node = load("res://tools/profile_world_impl.gd").new()
	get_root().add_child(n)
