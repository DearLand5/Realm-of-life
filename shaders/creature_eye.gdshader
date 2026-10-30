// Creature eyes. Attributes:
//   CUSTOM0 = (eye-local unit-sphere position: +Y gaze, +Z up, w = type * 4 + pupil)
//   COLOR   = iris colour, CUSTOM1 = (part id, 0), UV2.x = ao
// Types: 0 camera, 1 compound, 2 simple, 3 pit, 4 ocellus. Pupils: 0 round,
// 1 slit (vertical), 2 horizontal.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec4 v_loc;
varying vec3 v_iris;
varying float v_hl;

void vertex() {
	v_loc = CUSTOM0;
	v_iris = COLOR.rgb;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	vec3 p = normalize(v_loc.xyz);
	int code = int(v_loc.w + 0.5);
	int type = code / 4;
	int pupil = code - type * 4;
	vec3 n = normalize(NORMAL);
	vec3 col = v_iris;
	float rough = 0.06;
	float spec = 0.8;
	float cc = 0.0;
	vec3 emis = vec3(0.0);
	if (type == 0) {
		// Camera eye: iris + pupil on the gaze cap, sclera outside.
		float r = length(p.xz);
		float cap = p.y > 0.0 ? r : 2.0 - r;
		float iris_r = 0.62;
		float ang = atan(p.z, p.x);
		float fib = cv_vnoise(vec3(ang * 6.0, cap * 18.0, 1.0));
		vec3 iris = v_iris * (0.55 + 0.55 * fib) * mix(1.25, 0.6, smoothstep(0.0, iris_r, cap));
		iris = mix(iris, v_iris * 0.25, smoothstep(iris_r - 0.1, iris_r, cap));
		float pd;
		if (pupil == 1) {
			pd = length(vec2(p.x / 0.09, p.z / 0.42));
		} else if (pupil == 2) {
			pd = length(vec2(p.x / 0.4, p.z / 0.13));
		} else {
			pd = cap / 0.27;
		}
		float pupil_m = 1.0 - smoothstep(0.85, 1.05, pd);
		vec3 sclera = mix(vec3(0.86, 0.82, 0.74), v_iris * 0.5, 0.35);
		col = mix(sclera, iris, 1.0 - smoothstep(iris_r - 0.01, iris_r + 0.04, cap));
		col = mix(col, vec3(0.01), pupil_m);
		// Cornea: a sharp small highlight without washing the iris out.
		rough = 0.12;
		spec = 0.35;
		cc = 0.55;
	} else if (type == 1) {
		// Compound eye: hexagonal facets (offset grid in a stereographic projection).
		vec2 q = p.xz / (1.3 + p.y) * 26.0;
		vec2 g = vec2(q.x * 0.866, q.y + mod(floor(q.x * 0.866), 2.0) * 0.5);
		vec2 f = fract(g) - 0.5;
		float edge = smoothstep(0.32, 0.48, max(abs(f.x), abs(f.y)));
		col = mix(v_iris * 0.35, v_iris * 0.12, edge);
		col = cv_iridescent(col, 0.45, dot(n, VIEW), p * 3.0);
		n = cv_bump(n, VERTEX, -edge, 0.0006 * length(MODEL_MATRIX[0].xyz));
		rough = 0.18;
		spec = 0.7;
		cc = 0.5;
	} else if (type == 2 || type == 4) {
		// Simple eye / ocellus: glossy dark dome with a tinted lens.
		float c = smoothstep(0.2, 1.0, p.y);
		col = mix(v_iris * 0.12, v_iris * 0.4, c * 0.6) + vec3(0.01);
		rough = 0.05;
		spec = 0.85;
		cc = 1.0;
	} else {
		// Pit: dark recessed photoreceptor.
		col = mix(vec3(0.03), v_iris * 0.2, 0.3);
		rough = 0.5;
		spec = 0.3;
	}
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.03;
	NORMAL = n;
	EMISSION = emis + cv_highlight_emission(ndv, v_hl);
}
