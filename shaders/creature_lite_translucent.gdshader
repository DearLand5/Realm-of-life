// Lightweight translucent creature body for phones (membrane-covered organisms).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define CREATURE_TRANSLUCENT
#include "res://shaders/creature_common.gdshaderinc"
#include "res://shaders/creature_lite.gdshaderinc"
