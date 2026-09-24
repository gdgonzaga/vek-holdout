class_name TerrainTextureArrays
extends RefCounted
## Builds the three Texture2DArrays (albedo, normal, ORME) the terrain shader
## samples, from the material catalog's PbrTextureSets. Static and pure, so the
## visuals suite can drive it without a voxel terrain (SmoothGrid calls it).
##
## Layer layout: 0 = surface band material, 1 = deep band material, and
## `1 + palette_index` for the ore palette indices 1..15 that StrataBaker
## assigns (index 0 is the macro background). The shader picks a layer by
## coordinate, which replaces the old per-pixel sampler2D[16] indexing.
##
## Every layer of one array must share size and VRAM format or
## Texture2DArray.create_from_images fails. The packer guarantees that for
## packed sets; a layer that does not match (a hand-imported texture) is
## replaced by the neutral map and reported in `Result.problems`, never
## silently, and never by crashing map load.

const LAYER_SURFACE := 0
const LAYER_DEEP := 1
## 2 band layers + palette indices 1..15.
const MAX_LAYERS := 17
const DEFAULT_TILES_PER_METER := 0.25
## Flat colors used for band/ore layers whose def has neither a texture nor a
## color (the look the terrain had before textures existed).
const SURFACE_FALLBACK_TINT := Color(0.545, 0.435, 0.278)
const DEEP_FALLBACK_TINT := Color(0.541, 0.541, 0.561)
const ORE_FALLBACK_TINT := Color(0.541, 0.541, 0.561)

enum Role { ALBEDO, NORMAL, ORME }


class Result extends RefCounted:
	var albedo: Texture2DArray = null
	var normal: Texture2DArray = null
	var orme: Texture2DArray = null
	## Per-layer texture repeats per meter, MAX_LAYERS long.
	var tiles := PackedFloat32Array()
	## Per-layer albedo tint, MAX_LAYERS long. White for textured defs.
	var tints := PackedVector3Array()
	var layer_count := 0
	## Layers whose own map was rejected (wrong size/format) and replaced by neutral.
	var problems := PackedStringArray()


# =================
# Primary Functions
# =================

## Layer index for an ore palette index (1..15).
static func layer_for_palette_index(palette_index: int) -> int:
	return palette_index + 1


## Builds all three arrays plus the per-layer scalars. `ores_by_palette_index`
## maps int palette index -> TerrainMaterialDef. `neutral` defaults to the shared
## neutral set; null is returned when even that is missing (a broken install).
static func build(surface: TerrainMaterialDef, deep: TerrainMaterialDef,
		ores_by_palette_index: Dictionary, neutral: PbrTextureSet = null) -> Result:
	var reference := neutral if neutral != null else PbrTextureSet.neutral()
	if reference == null:
		push_error("TerrainTextureArrays: no neutral set (%s); run tools/pbr/pbr_pack_cli.gd -- --neutral neutral" % PbrTextureSet.NEUTRAL_PATH)
		return null
	# 1. Layer Mapping: Collect material definitions into indexed array slots.
	var defs := layer_defs(surface, deep, ores_by_palette_index)
	var result := Result.new()
	result.layer_count = defs.size()
	# 2. Array Assembly (Albedo): Construct albedo Texture2DArray across all layers.
	result.albedo = _build_array(defs, Role.ALBEDO, reference, result.problems)
	# 3. Array Assembly (Normal): Construct normal Texture2DArray across all layers.
	result.normal = _build_array(defs, Role.NORMAL, reference, result.problems)
	# 4. Array Assembly (ORME): Construct ORME Texture2DArray across all layers.
	result.orme = _build_array(defs, Role.ORME, reference, result.problems)
	# 5. Scalar Mapping (Tiles): Resolve triplanar repetition rates for each layer.
	result.tiles = layer_tiles(defs)
	# 6. Scalar Mapping (Tints): Resolve albedo tint vectors for each layer.
	result.tints = layer_tints(defs)
	# 7. Error Reporting: Emit any recorded layer mismatch diagnostics.
	_report_problems(result.problems)
	return result


## Albedo tint for a layer: white when the def has a real albedo (the texture
## carries its own color), the def's flat color when it has one, else `fallback`.
static func tint_for(def: TerrainMaterialDef, fallback: Color) -> Color:
	if def != null and PbrTextureSet.has_albedo(def.pbr):
		return Color.WHITE
	if def != null and def.color != Color.WHITE:
		return def.color
	return fallback


# ===================
# Auxiliary Functions
# ===================

static func layer_defs(surface: TerrainMaterialDef, deep: TerrainMaterialDef,
		ores_by_palette_index: Dictionary) -> Array[TerrainMaterialDef]:
	var highest := 0
	for palette_index: int in ores_by_palette_index:
		# Bounds check: Ensure palette index falls within valid 1..15 ore range.
		if _is_ore_index(palette_index):
			highest = maxi(highest, palette_index)
	var defs: Array[TerrainMaterialDef] = []
	defs.resize(layer_for_palette_index(highest) + 1)
	defs[LAYER_SURFACE] = surface
	defs[LAYER_DEEP] = deep
	for palette_index: int in ores_by_palette_index:
		# Bounds check: Ensure palette index falls within valid 1..15 ore range.
		if _is_ore_index(palette_index):
			defs[layer_for_palette_index(palette_index)] = ores_by_palette_index[palette_index]
	return defs


static func _is_ore_index(palette_index: int) -> bool:
	return palette_index >= 1 and palette_index <= MAX_LAYERS - 2


static func _build_array(defs: Array[TerrainMaterialDef], role: Role, reference: PbrTextureSet,
		problems: PackedStringArray) -> Texture2DArray:
	# Reference Texture Extraction: Retrieve role texture and convert to CPU Image for layout comparison.
	var neutral_image := texture_image(_role_texture(reference, role))
	var images: Array[Image] = []
	for def: TerrainMaterialDef in defs:
		# Layer Processing: Select matching material map or fallback neutral image.
		images.append(layer_image(def, role, neutral_image, problems))
	var array := Texture2DArray.new()
	var error := array.create_from_images(images)
	if error != OK:
		problems.append("could not assemble the %s array (error %d)" % [Role.keys()[role].to_lower(), error])
	return array


static func layer_image(def: TerrainMaterialDef, role: Role, neutral_image: Image,
		problems: PackedStringArray) -> Image:
	# Role Mapping: Extract specific texture map from definition PBR set.
	var texture := _role_texture(def.pbr if def != null else null, role)
	if texture == null:
		return neutral_image
	# Image Extraction: Acquire CPU Image representation of the texture.
	var image := texture_image(texture)
	# Layout Validation: Verify dimension, format, and mipmap parity with reference.
	if _is_layout_compatible(image, neutral_image):
		return image
	problems.append("'%s' %s map does not match the shared layer layout (size, format, mipmaps); using the neutral map. Re-pack it with tools/pbr/pbr_pack_cli.gd." % [
		def.id, Role.keys()[role].to_lower()])
	return neutral_image


static func _role_texture(texture_set: PbrTextureSet, role: Role) -> Texture2D:
	if texture_set == null:
		return null
	match role:
		Role.ALBEDO:
			return texture_set.albedo
		Role.NORMAL:
			return texture_set.normal
		_:
			return texture_set.orme


static func texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	return texture.get_image()


static func _is_layout_compatible(image: Image, reference: Image) -> bool:
	return image != null and reference != null \
			and image.get_size() == reference.get_size() \
			and image.get_format() == reference.get_format() \
			and image.get_mipmap_count() == reference.get_mipmap_count()


static func layer_tiles(defs: Array[TerrainMaterialDef]) -> PackedFloat32Array:
	var tiles := PackedFloat32Array()
	tiles.resize(MAX_LAYERS)
	tiles.fill(DEFAULT_TILES_PER_METER)
	for i: int in defs.size():
		if defs[i] != null:
			tiles[i] = defs[i].tiles_per_meter
	return tiles


static func layer_tints(defs: Array[TerrainMaterialDef]) -> PackedVector3Array:
	var tints := PackedVector3Array()
	tints.resize(MAX_LAYERS)
	tints.fill(Vector3.ONE)
	# Surface Tint Resolution: Convert surface layer color to Vector3.
	tints[LAYER_SURFACE] = _tint_vector(defs[LAYER_SURFACE], SURFACE_FALLBACK_TINT)
	# Deep Tint Resolution: Convert deep layer color to Vector3.
	tints[LAYER_DEEP] = _tint_vector(defs[LAYER_DEEP], DEEP_FALLBACK_TINT)
	for i: int in range(LAYER_DEEP + 1, defs.size()):
		# Ore Tint Resolution: Convert ore layer color to Vector3.
		tints[i] = _tint_vector(defs[i], ORE_FALLBACK_TINT)
	return tints


static func _tint_vector(def: TerrainMaterialDef, fallback: Color) -> Vector3:
	# Color Evaluation: Determine effective color tint based on texture presence.
	var tint := tint_for(def, fallback)
	return Vector3(tint.r, tint.g, tint.b)


static func _report_problems(problems: PackedStringArray) -> void:
	for problem: String in problems:
		push_error("TerrainTextureArrays: %s" % problem)
