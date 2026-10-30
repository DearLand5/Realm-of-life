shader_type canvas_item;
// First-person "how this animal sees" post effect + damage vignette.
// Works in the mobile and compatibility renderers (canvas screen texture only).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float gray : hint_range(0.0, 1.0) = 0.0;         // 1 = monochrome (no colour vision)
uniform float darkness : hint_range(0.0, 1.0) = 0.0;     // dim light, reduced by night vision
uniform vec3 night_tint = vec3(0.55, 0.75, 1.0);
uniform float blur : hint_range(0.0, 1.0) = 0.0;         // low acuity
uniform float mosaic : hint_range(0.0, 1.0) = 0.0;       // compound eyes: facets
uniform float facet_size = 14.0;
uniform float edge_blur : hint_range(0.0, 1.0) = 0.0;    // peripheral blur
uniform float damage : hint_range(0.0, 1.0) = 0.0;       // red edge vignette
uniform float pulse = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	if (mosaic > 0.01) {
		// Hexagon-ish facets: snap to a grid, offset every other row.
		vec2 cell = vec2(facet_size, facet_size * 0.866) / res;
		float row = floor(uv.y / cell.y);
		vec2 p = vec2(uv.x + mod(row, 2.0) * cell.x * 0.5, uv.y);
		vec2 snapped = (floor(p / cell) + 0.5) * cell;
		snapped.x -= mod(row, 2.0) * cell.x * 0.5;
		uv = mix(uv, snapped, mosaic);
	}
	float centre = length(SCREEN_UV - 0.5);
	float lod = blur * 4.5 + edge_blur * smoothstep(0.15, 0.7, centre) * 3.0;
	vec3 c = textureLod(screen_tex, uv, lod).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), gray);
	// Darkness: dim, desaturate towards a cool tint (rods only).
	vec3 night = vec3(l) * night_tint * 1.6;
	c = mix(c, night, darkness * 0.85);
	c *= 1.0 - darkness * 0.45;
	// Damage: red vignette that pulses.
	float v = smoothstep(0.25, 0.85, centre);
	c = mix(c, vec3(0.75, 0.04, 0.04), clamp(damage * v * (0.75 + 0.25 * sin(pulse)), 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
