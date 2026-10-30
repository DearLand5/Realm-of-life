extends SceneTree
## Thin launcher: opens the real world scene and takes screenshots.
##   tools/shot.sh tools/preview_world_hud.gd -- [out_prefix] [page]
func _initialize() -> void:
	await process_frame
	var runner: Node = load("res://tools/preview_world_hud_impl.gd").new()
	root.add_child(runner)
