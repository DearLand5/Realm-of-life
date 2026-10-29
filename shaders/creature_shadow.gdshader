// Cheap contact (blob) shadow under a creature: a ground quad with a soft
// elliptical falloff. UV 0..1 over the quad; strength via instance uniform.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

instance uniform float cv_shadow_strength = 0.55;

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	float a = (1.0 - smoothstep(0.15, 1.0, r));
	ALBEDO = vec3(0.0);
	ALPHA = a * a * clamp(cv_shadow_strength, 0.0, 1.0);
}
