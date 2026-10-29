class_name CreatureMaterials
extends RefCounted
## Shared creature materials (one ShaderMaterial per kind for all creatures)
## and the per-individual instance-uniform values that make every individual
## look like itself: expressed covering colours with slight seed jitter,
## pattern parameters, condition, highlight. Main thread only.

const SHADER_PATHS := {
	&"body": "res://shaders/creature.gdshader",
	&"body_translucent": "res://shaders/creature_translucent.gdshader",
	&"hard": "res://shaders/creature_hard.gdshader",
	&"eye": "res://shaders/creature_eye.gdshader",
	&"membrane": "res://shaders/creature_membrane.gdshader",
	&"feather": "res://shaders/creature_feather.gdshader",
	&"glow": "res://shaders/creature_glow.gdshader",
	&"organelle": "res://shaders/creature_organelle.gdshader",
	&"organ": "res://shaders/creature_organ.gdshader",
	&"xray": "res://shaders/creature_xray.gdshader",
	&"shadow": "res://shaders/creature_shadow.gdshader",
}

## Covering type -> shader type id (creature_common.gdshaderinc T_* constants).
const TYPE_IDS := {
	&"skin": 0, &"scales": 1, &"plates": 2, &"shell": 3, &"chitin": 4,
	&"fur": 5, &"feathers": 6, &"bristles": 7, &"slime": 8, &"membrane": 9,
}

## Per-individual colour jitter (fractions).
const HUE_JITTER := 0.018
const SAT_JITTER := 0.06
const VAL_JITTER := 0.07

static var _materials := {}


## Shared material of a kind (CreatureBuildContext.KIND_* or &"body_translucent",
## &"xray", &"shadow"). Never modify the returned material per creature: use
## instance parameters.
static func material(kind: StringName) -> ShaderMaterial:
	if _materials.has(kind):
		return _materials[kind]
	var path: String = SHADER_PATHS.get(kind, SHADER_PATHS[&"body"])
	var sh := load(path) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	if kind == &"xray":
		mat.render_priority = 1
	_materials[kind] = mat
	return mat


## Body material kind for a model: translucent for membrane-covered bodies.
static func body_kind(model: AnatomyModel) -> StringName:
	if model != null and not model.coverings.is_empty() and model.coverings[0].type == &"membrane":
		return &"body_translucent"
	return &"body"


static func type_id(t: StringName) -> int:
	return int(TYPE_IDS.get(t, 0))


static func pattern_id(p: StringName) -> int:
	return maxi(CoveringDef.PATTERNS.find(p), 0)


## Instance-uniform values for a model and individual seed.
static func instance_params(model: AnatomyModel, individual_seed: int, char_size: float) -> Dictionary:
	var out := {}
	var covs: Array[CoveringDef] = []
	if model != null:
		covs = model.coverings
	var rng := Rng.new(hash(individual_seed) ^ 0x5bd1e995)
	var thick := Vector4.ONE
	for i in 4:
		var c: CoveringDef = covs[mini(i, covs.size() - 1)] if not covs.is_empty() else CoveringDef.new()
		var dh := rng.range_f(-HUE_JITTER, HUE_JITTER)
		var ds := rng.range_f(-SAT_JITTER, SAT_JITTER)
		var dv := rng.range_f(-VAL_JITTER, VAL_JITTER)
		# Coverings are authored in sRGB; shaders work in linear space.
		var ca := _jitter(c.color_a, dh, ds, dv).srgb_to_linear()
		var cb := _jitter(c.color_b, dh * 0.7, ds, dv * 0.7).srgb_to_linear()
		out["cv_slot%d_a" % i] = Vector4(ca.r, ca.g, ca.b, float(type_id(c.type)))
		out["cv_slot%d_b" % i] = Vector4(cb.r, cb.g, cb.b, float(pattern_id(c.pattern)))
		out["cv_slot%d_p" % i] = Vector4(clampf(c.pattern_scale, 0.1, 5.0) * rng.range_f(0.94, 1.06),
			clampf(c.pattern_contrast, 0.0, 1.0), clampf(c.roughness_bias, -0.5, 0.5), clampf(c.iridescence, 0.0, 1.0))
		thick[i] = clampf(c.thickness, 0.1, 4.0)
	out["cv_slot_thick"] = thick
	out["cv_individual"] = Vector4(seed01(individual_seed), 1.0 / maxf(char_size, 1e-4), 0.0, 0.0)
	return out


static func seed01(s: int) -> float:
	return float(hash(s) & 0xFFFF) / 65535.0


static func _jitter(c: Color, dh: float, ds: float, dv: float) -> Color:
	var h := wrapf(c.h + dh, 0.0, 1.0)
	var s := clampf(c.s * (1.0 + ds), 0.0, 1.0)
	var v := clampf(c.v * (1.0 + dv), 0.0, 1.0)
	return Color.from_hsv(h, s, v)


static func apply(gi: GeometryInstance3D, params: Dictionary) -> void:
	if gi == null:
		return
	for k in params:
		gi.set_instance_shader_parameter(StringName(k), params[k])
