class_name PbrMaterialFactory
extends RefCounted
## Builds render materials from a PbrTextureSet for blocks and furniture (the
## terrain does not use materials: it feeds the same sets to one shader through
## TerrainTextureArrays). Static, stateless, safe to call from @tool code: it is
## a separate class on purpose, because instance helpers on a def resource bind
## to stale bytecode in the editor (see BuildableDef's class doc).

const BLOCK_SHADER: Shader = preload("res://assets/shaders/block_shader.gdshader")


# =================
# Primary Functions
# =================

## StandardMaterial3D from the set. Maps the set lacks are simply left unbound.
static func standard(texture_set: PbrTextureSet) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if texture_set == null:
		return material
	if texture_set.albedo != null:
		material.albedo_texture = texture_set.albedo
	if texture_set.normal != null:
		# Normal map enabled so the texture's own import flag decides how it decodes.
		material.normal_enabled = true
		material.normal_texture = texture_set.normal
	if texture_set.orme != null:
		# Wire ORME channels to ambient occlusion, roughness, and metallic on the material.
		_bind_orme(material, texture_set.orme)
	return material


## The per-block UV/brightness variation shader, with every map bound. The
## shader has no missing-map branch, so a map the set lacks comes from `neutral`
## (defaults to the shared neutral set).
static func variation(texture_set: PbrTextureSet, neutral: PbrTextureSet = null) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BLOCK_SHADER
	var fill := neutral if neutral != null else PbrTextureSet.neutral()
	# Resolve preferred albedo map or fallback neutral fill to ensure uniform binding.
	material.set_shader_parameter("albedo_tex", _first(_albedo_of(texture_set), _albedo_of(fill)))
	# Resolve preferred normal map or fallback neutral fill to ensure flat normal fallback.
	material.set_shader_parameter("normal_tex", _first(_normal_of(texture_set), _normal_of(fill)))
	# Resolve preferred ORME map or fallback neutral fill to ensure unoccluded, rough, non-metal fallback.
	material.set_shader_parameter("orme_tex", _first(_orme_of(texture_set), _orme_of(fill)))
	return material


# ===================
# Auxiliary Functions
# ===================

static func _bind_orme(material: StandardMaterial3D, orme: Texture2D) -> void:
	## Auxiliary: Configures ORME channels (R: AO, G: Roughness, B: Metallic) on a StandardMaterial3D.
	material.ao_enabled = true
	material.ao_texture = orme
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness_texture = orme
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	# Metallic scales the texture, so 1.0 lets the B channel alone decide.
	material.metallic = 1.0
	material.metallic_texture = orme
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE


static func _albedo_of(texture_set: PbrTextureSet) -> Texture2D:
	## Auxiliary: Extracts albedo texture safely from a nullable PbrTextureSet.
	return texture_set.albedo if texture_set != null else null


static func _normal_of(texture_set: PbrTextureSet) -> Texture2D:
	## Auxiliary: Extracts normal texture safely from a nullable PbrTextureSet.
	return texture_set.normal if texture_set != null else null


static func _orme_of(texture_set: PbrTextureSet) -> Texture2D:
	## Auxiliary: Extracts ORME texture safely from a nullable PbrTextureSet.
	return texture_set.orme if texture_set != null else null


static func _first(preferred: Texture2D, fallback: Texture2D) -> Texture2D:
	## Auxiliary: Selects preferred texture if non-null, otherwise returns fallback.
	return preferred if preferred != null else fallback
