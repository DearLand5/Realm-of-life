// Opaque creature body (see creature_body.gdshaderinc). Works in the mobile
// and gl_compatibility renderers (no screen/depth textures, no compute).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"
#include "res://shaders/creature_body.gdshaderinc"
