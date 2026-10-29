class_name AccessoryBuilder
extends RefCounted
## Dispatches every AnatomyModel accessory to its procedural mesh builder.
## Builders write into the context buffers by material kind; unknown types
## are reported in ctx.warnings and skipped (forward compatibility).


static func build_all(ctx: CreatureBuildContext) -> void:
	for a in ctx.model.accessories:
		if a == null:
			continue
		build_one(ctx, a)


static func build_one(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	match a.type:
		&"tube", &"shell":
			pass  # tubes are built by CreatureMeshBuilder, shells are part of the SDF
		_:
			if not ctx.warnings.has("unknown accessory " + str(a.type)):
				ctx.warnings.append("unknown accessory " + str(a.type))
