extends SceneTree
## Runtime previews: the arena with several presets moving, first-person view of a
## predator, third-person HUD with context buttons.
##   tools/shot.sh tools/preview_runtime.gd -- all            (writes screenshots/runtime_*.png)
##   tools/shot.sh tools/preview_runtime.gd -- arena|first|third [out.png]
## The work happens in preview_runtime_scene.gd, loaded after the first frame so
## autoload singletons (EventBus, Game) exist when runtime scripts compile.


func _initialize() -> void:
	await process_frame
	var scene: Node = load("res://tools/preview_runtime_scene.gd").new()
	get_root().add_child(scene)
	await scene.run(OS.get_cmdline_user_args())
	quit()
