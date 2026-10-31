extends SceneTree
## Thin launcher for gpu_breakdown_impl.gd (relative render cost of world parts).
##   xvfb-run godot --rendering-driver vulkan --rendering-method mobile -s tools/gpu_breakdown.gd

func _initialize() -> void:
	await process_frame
	get_root().add_child(load("res://tools/gpu_breakdown_impl.gd").new())
