// Lightweight opaque creature body for phones (see creature_lite.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"
#include "res://shaders/creature_lite.gdshaderinc"
