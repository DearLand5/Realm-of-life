shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;
// Soft round stage floor: fades into the background, faint rings and a
// sagittal-plane line. Works in both Forward Mobile and Compatibility.

uniform vec3 base_color : source_color = vec3(0.10, 0.17, 0.17);
uniform vec3 line_color : source_color = vec3(0.45, 0.7, 0.65);
uniform float radius = 5.0;
uniform float ring_step = 1.0;
uniform float show_axis = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float d = length(local_pos.xz);
	float fade = 1.0 - smoothstep(radius * 0.55, radius, d);
	float ring = abs(fract(d / ring_step + 0.5) - 0.5) * ring_step;
	float ring_line = 1.0 - smoothstep(0.0, 0.012 * (1.0 + d * 0.15), ring);
	float axis_line = (1.0 - smoothstep(0.0, 0.012, abs(local_pos.x))) * show_axis;
	float line = max(ring_line * 0.09, axis_line * 0.16);
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 0.95;
	ALPHA = fade;
}
