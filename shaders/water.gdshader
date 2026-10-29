// Water for ocean, lakes and river ribbons (mobile-cheap, no screen/depth textures).
// Vertex data (see WaterMesher): UV2.x = water depth above the ground (m),
// UV = river coordinates (across 0..1, along in metres) when `river` is set.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/terrain_noise.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.16, 0.52, 0.52);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.22);
uniform vec3 sky_color : source_color = vec3(0.6, 0.74, 0.9);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec2 wind = vec2(2.0, 0.5);       // m/s, world xz
uniform float wave_height = 0.12;
uniform float daylight = 1.0;
uniform float rain = 0.0;                 // rain ripples / dulling
uniform bool river = false;
uniform float flow_speed = 0.7;           // m/s along the ribbon

varying float v_depth;
varying vec3 v_world;
varying vec2 v_uv;

void vertex() {
	v_depth = UV2.x;
	v_uv = UV;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wl = length(wind);
	vec2 dir = wl > 0.01 ? wind / wl : vec2(1.0, 0.0);
	float amp = river ? 0.0 : wave_height * (0.35 + 0.65 * clamp(wl / 9.0, 0.0, 1.0)) * smoothstep(0.3, 4.0, v_depth);
	float ph = dot(dir, wp.xz);
	float ph2 = dot(vec2(-dir.y, dir.x), wp.xz);
	VERTEX.y += amp * (sin(ph * 0.33 - TIME * 1.15) + 0.45 * sin(ph * 0.71 + ph2 * 0.3 - TIME * 1.9) + 0.25 * sin(ph2 * 0.9 + TIME * 1.3));
	v_world = wp;
}

// Two scrolling noise layers -> surface slope (world xz).
vec2 ripple_slope(vec2 p, vec2 flow, float t) {
	float e = 0.15;
	vec2 p1 = p * 0.55 + flow * t * 0.35;
	vec2 p2 = p * 1.37 - flow.yx * t * 0.5 + vec2(13.7, 7.1);
	float a = rl_vnoise(p1);
	float b = rl_vnoise(p2);
	float ax = rl_vnoise(p1 + vec2(e, 0.0)) - a;
	float az = rl_vnoise(p1 + vec2(0.0, e)) - a;
	float bx = rl_vnoise(p2 + vec2(e, 0.0)) - b;
	float bz = rl_vnoise(p2 + vec2(0.0, e)) - b;
	return (vec2(ax, az) * 0.55 + vec2(bx, bz) * 1.37 * 0.5) / e;
}

void fragment() {
	float wl = length(wind);
	vec2 dir = wl > 0.01 ? wind / wl : vec2(1.0, 0.0);
	vec2 flow = dir;
	vec2 p = v_world.xz;
	float strength = 0.1 + 0.08 * clamp(wl / 8.0, 0.0, 1.0);
	if (river) {
		// Ripples run along the ribbon.
		p = vec2(v_uv.x * 3.0, v_uv.y);
		flow = vec2(0.0, -flow_speed * 1.6);
		strength = 0.16;
	}
	vec2 s = ripple_slope(p, flow, TIME) * strength;
	s += (rl_vnoise(p * 4.0 + TIME * 3.0) - 0.5) * rain * 0.3;
	vec3 wn = normalize(vec3(-s.x, 1.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	float depth = max(v_depth, 0.0);
	float d = clamp(depth / 7.0, 0.0, 1.0);
	vec3 body = mix(shallow_color, deep_color, sqrt(d));
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.03 + 0.97 * pow(1.0 - ndv, 5.0);
	fresnel = clamp(fresnel * (1.0 - rain * 0.3), 0.0, 1.0);

	// Shore foam: animated band where the water gets thin.
	float n = rl_vnoise(v_world.xz * 0.9 + TIME * 0.3);
	float band = 1.0 - smoothstep(0.0, 0.45, depth + (n - 0.5) * 0.25);
	float pulse = 0.55 + 0.45 * sin(TIME * 1.4 - depth * 9.0 + n * 3.0);
	float foam = band * smoothstep(0.35, 0.65, n * 0.6 + pulse * 0.6);
	if (river) {
		float edge = abs(v_uv.x - 0.5) * 2.0;
		foam = smoothstep(0.88, 1.0, edge) * 0.35 * n;
	}

	ALBEDO = mix(body * (1.0 - fresnel), foam_color, foam);
	EMISSION = sky_color * fresnel * (0.35 + 0.65 * daylight) * (1.0 - foam);
	ROUGHNESS = mix(0.06, 0.5, max(foam, rain * 0.6));
	SPECULAR = 0.55;
	ALPHA = clamp(mix(0.25, 0.94, smoothstep(0.0, 2.8, depth)) + foam * 0.6 + fresnel * 0.3, 0.0, 1.0);
}
