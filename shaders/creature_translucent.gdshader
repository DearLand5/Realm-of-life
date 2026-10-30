// Translucent creature body for membrane-covered organisms (cells, jellyfish):
// alpha from the covering look (fresnel-weighted), internal organelles show
// through. Same attributes and parameters as creature.gdshader.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define CREATURE_TRANSLUCENT
#include "res://shaders/creature_common.gdshaderinc"
#include "res://shaders/creature_body.gdshaderinc"
