class_name RlNoise
extends RefCounted
## Tileable value-noise textures for the world shaders (terrain_noise.gdshaderinc):
## one texture fetch replaces 4 hashes + interpolation per octave, which made
## the terrain/plant/water shaders far too heavy for phone GPUs. Generated once
## per run by FastNoiseLite (C++), no image files.
##
##   mat.set_shader_parameter("rl_noise_v", RlNoise.value_texture())
##   RlNoise.bind(mat)    # sets both textures

const SIZE := 256
## Noise cells across the texture: shaders sample at p / CELLS for unit cells.
const CELLS := 64

static var _value: ImageTexture
static var _fbm: ImageTexture


static func value_texture() -> Texture2D:
	if _value == null:
		_value = _make(false)
	return _value


static func fbm_texture() -> Texture2D:
	if _fbm == null:
		_fbm = _make(true)
	return _fbm


## Binds both noise textures to a material using terrain_noise.gdshaderinc.
static func bind(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("rl_noise_v", value_texture())
	mat.set_shader_parameter("rl_noise_f", fbm_texture())


static func _make(fbm: bool) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	n.seed = 1337 if fbm else 4242
	n.frequency = float(CELLS) / float(SIZE)
	if fbm:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.fractal_lacunarity = 2.0
		n.fractal_gain = 0.6
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	var img := n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
