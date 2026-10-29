// Terrain: biome vertex colours + procedural detail (no textures).
// Vertex data (see TerrainMesher): COLOR.rgb ground colour, COLOR.a grass factor,
// UV = (height above nearest water surface, annual mean °C), UV2 = (moisture, rock factor).
// Colours are authored/combined in sRGB and converted to linear at the end.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/terrain_noise.gdshaderinc"

uniform float sea_level = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;
uniform float temp_offset = 0.0;          // seasonal + weather anomaly (°C)
uniform vec3 grass_tint = vec3(1.0);       // multiplicative, sRGB space
uniform float dryness : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float detail_distance = 140.0;    // micro detail fades out beyond this

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_data;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_data = vec4(UV, UV2);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float grass = COLOR.a;
	float shore = v_data.x;
	float temp = v_data.y + temp_offset;
	float moist = v_data.z;
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(detail_distance * 0.4, detail_distance, dist);
	vec2 p = v_world.xz;
	vec3 wn = normalize(v_wnormal);

	float macro = rl_fbm3(p * 0.03);
	float meso = rl_vnoise(p * 0.19);
	float micro = mix(0.5, rl_vnoise(p * 1.3), near);
	float grain = mix(0.5, rl_vnoise(p * 5.1), near * near);

	// Ground variation: large soft patches + fine mottling.
	col *= 0.84 + 0.32 * macro + 0.14 * (meso - 0.5) + 0.12 * (micro - 0.5) + 0.06 * (grain - 0.5);
	// Patches of lighter/darker grass, bare soil and fine grass strokes near the camera.
	float patch = smoothstep(0.35, 0.75, rl_fbm3(p * 0.11 + 3.0));
	vec3 g = col * grass_tint;
	g = mix(g, g * vec3(1.12, 1.08, 0.86), patch * 0.5);
	float soil = smoothstep(0.62, 0.8, rl_fbm3(p * 0.07 + 11.0) + (0.45 - moist) * 0.4);
	g = mix(g, vec3(0.44, 0.36, 0.26) * (0.9 + 0.2 * meso), soil * 0.55);
	float strokes = rl_vnoise(vec2(p.x * 7.0 + p.y * 2.0, p.y * 7.0 - p.x * 1.5));
	g *= 1.0 + (strokes - 0.5) * 0.22 * near;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 straw = vec3(0.74, 0.63, 0.38) * (lum * 1.5 + 0.12);
	g = mix(g, straw, clamp(dryness * (0.55 + 0.6 * (1.0 - moist)), 0.0, 1.0));
	col = mix(col, g, grass);

	float slope = 1.0 - wn.y;
	float rock_n = rl_triplanar(v_world, wn, 0.35);

	// Beach sand near the sea on gentle shores; lake/river banks get mud and
	// gravel; cold shores are grey shingle.
	float water_level = v_world.y - shore;
	float lake_shore = smoothstep(0.3, 1.0, water_level - sea_level);
	float sand = 1.0 - smoothstep(0.3, 1.5, shore + (meso - 0.5) * 0.9);
	sand *= 1.0 - smoothstep(0.12, 0.32, slope);
	vec3 sand_col = mix(vec3(0.80, 0.73, 0.55), vec3(0.55, 0.54, 0.50), smoothstep(6.0, 0.0, temp));
	sand_col = mix(sand_col, vec3(0.42, 0.38, 0.30) * (0.9 + 0.25 * meso), lake_shore);
	sand_col *= 0.9 + 0.2 * grain;
	col = mix(col, sand_col, sand * step(-0.3, shore) * (1.0 - 0.45 * lake_shore));

	// Exposed rock on slopes and rocky biomes (triplanar, layered strata).
	float rock = smoothstep(0.27, 0.5, slope + (rock_n - 0.5) * 0.2 + v_data.w * 0.16);
	float strata = mix(0.5, sin(v_world.y * 1.3 + rock_n * 5.0) * 0.5 + 0.5, near);
	vec3 rock_col = mix(vec3(0.40, 0.37, 0.33), vec3(0.60, 0.56, 0.50), rock_n);
	rock_col *= 0.9 + 0.1 * strata + 0.12 * (rl_triplanar(v_world, wn, 2.1) - 0.5) * near;
	// Lichen/moss on gentler rock in wet places.
	rock_col = mix(rock_col, vec3(0.36, 0.40, 0.26), smoothstep(0.55, 0.9, moist) * (1.0 - smoothstep(0.3, 0.6, slope)) * 0.5);
	col = mix(col, rock_col, rock);

	// Under water: silty and dark with depth (water shader tints on top).
	float under = smoothstep(0.0, -0.6, shore);
	col = mix(col, col * vec3(0.72, 0.74, 0.66), under);

	// Wet shoreline band + rain wetness.
	float wet = (1.0 - smoothstep(-0.05, 0.45, shore + (micro - 0.5) * 0.3)) * (1.0 - under * 0.5);
	wet = max(wet, wetness * 0.65 * (1.0 - rock * 0.3));
	col *= 1.0 - 0.38 * wet;

	// Snow: permanent where very cold, fresh cover below freezing; flat ground first.
	float perm = smoothstep(-3.0, -7.0, temp);
	float fresh = snow_cover * smoothstep(1.5, -1.5, temp);
	float flat_f = smoothstep(0.42, 0.78, wn.y + (meso - 0.5) * 0.25);
	float snow = clamp((perm + fresh) * flat_f * 1.4 - (rock_n - 0.5) * 0.4, 0.0, 1.0);
	snow = smoothstep(0.25, 0.6, snow + (micro - 0.5) * 0.25) * step(0.0, shore);
	col = mix(col, vec3(0.9, 0.93, 0.98) * (0.95 + 0.05 * grain), snow);

	ALBEDO = pow(max(col, vec3(0.0)), vec3(2.2));
	ROUGHNESS = mix(0.95, 0.38, max(wet, snow * 0.4));
	SPECULAR = mix(0.25, 0.5, wet);
}
