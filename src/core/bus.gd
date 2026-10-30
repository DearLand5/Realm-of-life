class_name Bus
extends RefCounted
## Late-bound access to the EventBus autoload for model classes that may be
## compiled before autoloads exist (tools run with `godot -s`, tests).


static func node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("EventBus")
	return null


static func emit(signal_name: StringName, args: Array = []) -> void:
	var b := node()
	if b != null and b.has_signal(signal_name):
		b.callv("emit_signal", [signal_name] + args)
