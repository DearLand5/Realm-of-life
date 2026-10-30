extends SceneTree
## Renders a generated world (terrain, water, flora, sky, weather) from
## several viewpoints, times of day and weather states.
##   tools/shot.sh tools/preview_world.gd -- [set] [seed] [out_dir]
## set: all | overview | ground | times | weather | final | <shot name>
## "final" writes screenshots/world_overview.png, world_ground.png, world_weather.png.
## The work happens in preview_world_scene.gd, loaded after the first frame so
## autoload singletons (EventBus, Game) exist when world scripts compile.


func _initialize() -> void:
	await process_frame
	var scene: Node = load("res://tools/preview_world_scene.gd").new()
	get_root().add_child(scene)
	await scene.run(OS.get_cmdline_user_args())
	quit()
