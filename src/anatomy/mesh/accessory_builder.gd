class_name AccessoryBuilder
extends RefCounted
## Dispatches every AnatomyModel accessory to its procedural mesh builder.
## Builders write into the context buffers by material kind; unknown types
## are reported in ctx.warnings and skipped (forward compatibility).


static func build_all(ctx: CreatureBuildContext) -> void:
	for a in ctx.model.accessories:
		if a == null:
			continue
		if a.bone < 0 or a.bone >= ctx.model.bones.size() or not a.transform.is_finite():
			ctx.warnings.append("accessory %s with invalid bone/transform skipped" % a.type)
			continue
		build_one(ctx, a)


static func build_one(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	match a.type:
		&"eye":
			EyeBuilder.build(ctx, a)
		&"horn":
			AppendageBuilder.horn(ctx, a, AppendageBuilder.CODE_HORN)
		&"spike":
			AppendageBuilder.horn(ctx, a, AppendageBuilder.CODE_SPIKE)
		&"claw":
			AppendageBuilder.horn(ctx, a, AppendageBuilder.CODE_CLAW)
		&"whisker":
			AppendageBuilder.whiskers(ctx, a)
		&"ear":
			HeadPartBuilder.ear(ctx, a)
		&"nose":
			HeadPartBuilder.nose(ctx, a)
		&"mouth":
			MouthBuilder.build(ctx, a)
		&"foot":
			FootBuilder.build(ctx, a)
		&"membrane":
			MembraneBuilder.build(ctx, a)
		&"fluke":
			MembraneBuilder.fluke(ctx, a)
		&"gill":
			MiscPartBuilder.gill(ctx, a)
		&"sensor":
			MiscPartBuilder.sensor(ctx, a)
		&"gland":
			MiscPartBuilder.gland(ctx, a)
		&"light":
			MiscPartBuilder.light(ctx, a)
		&"cell_organelle":
			MiscPartBuilder.organelle(ctx, a)
		&"organ":
			MiscPartBuilder.organ(ctx, a)
		&"tube", &"shell":
			pass  # tubes are built by CreatureMeshBuilder, shells are part of the SDF
		_:
			var msg := "unknown accessory " + str(a.type)
			if not ctx.warnings.has(msg):
				ctx.warnings.append(msg)
