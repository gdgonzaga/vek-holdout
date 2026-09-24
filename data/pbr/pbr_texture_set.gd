class_name PbrTextureSet
extends Resource
## One material's texture maps as a set: albedo, normal, and a packed ORME map
## (Occlusion R, Roughness G, Metallic B, Extra A). Shared by TerrainMaterialDef
## and BuildableDef so the project has a single channel convention.
##
## Sets are produced by tools/pbr/pbr_pack_cli.gd from ambientCG-style
## downloads. A missing source map is filled with the NEUTRAL_* values at pack
## time, so a packed set is always complete. The fields stay nullable because
## albedo-only sets (blocks, furniture) are legitimate; consumers that need all
## three maps (TerrainTextureArrays) substitute the neutral set map by map.
##
## Conventions (docs/HOWTO-author-pbr-textures.md): albedo is sRGB, normal is
## OpenGL (Y+), ORME is linear. Extra (A) is reserved and always packed as 0.

## Where the shared neutral set lives. Loaded lazily by path: a preload here
## would make this script and neutral.tres depend on each other.
const NEUTRAL_PATH := "res://data/pbr/neutral.tres"
## Flat tangent-space normal: no bumps. 8-bit (128, 128, 255): Color(0.5, ...)
## would store as 127 in an RGB8 image and tilt the "flat" normal slightly.
const NEUTRAL_NORMAL := Color8(128, 128, 255, 255)
## No occlusion (R), fully rough (G), non-metal (B), no extra (A). Roughness 1.0
## matches the terrain's pre-PBR look, so an unmapped material renders as before.
const NEUTRAL_ORME := Color(1.0, 1.0, 0.0, 0.0)

static var _neutral: PbrTextureSet = null

@export var id: String
@export var albedo: Texture2D = null
@export var normal: Texture2D = null
@export var orme: Texture2D = null


## True when the set exists and carries at least one map.
static func has_any(texture_set: PbrTextureSet) -> bool:
	return texture_set != null \
			and (texture_set.albedo != null or texture_set.normal != null or texture_set.orme != null)


## True when the set exists and carries an albedo map.
static func has_albedo(texture_set: PbrTextureSet) -> bool:
	return texture_set != null and texture_set.albedo != null


## The shared all-neutral set (flat normal, unoccluded rough non-metal ORME,
## white albedo). Null only if the neutral assets were never generated.
static func neutral() -> PbrTextureSet:
	if _neutral == null:
		_neutral = load(NEUTRAL_PATH) as PbrTextureSet
	return _neutral
