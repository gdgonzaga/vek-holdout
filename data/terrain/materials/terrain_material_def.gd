extends Resource
class_name TerrainMaterialDef
## Identity + mining stats for a natural material of the smooth terrain (dirt,
## rock, ores). One of the mirrored BlockyGrid/SmoothGrid vocabularies
## (docs/TODO.md D1/D2).
##
## Identity is per-position at runtime: authored blobs (editor sculpts, smooth
## placement, structure stamps) carry their material id in per-block voxel
## metadata (F12 — one Dictionary per 16^3 block anchored at the block origin);
## natural ground resolves through TerrainStrata's deterministic depth rules.
## The mesher remains a one-look-per-map ceiling — per-voxel texturing is
## verified non-functional (F14) — so visuals are INDIRECT: the terrain shader
## bands the two `band_material` endpoints' look by depth (F11 shader rules),
## and authored blobs each get a Decal marker tinted `color`. Equipment gating
## (later) matches on `id`.

@export var id: String
@export var display_name: String

## Visual identity color: tints the depth-band look when this material is a
## band endpoint without a `texture`, and tints the Decal marker that makes
## authored blobs of this material visually distinct (iron vs gold at a
## glance). White reads as "no tint".
@export var color: Color = Color.WHITE

## Break pool. Today it scales dig time (work_time * hp / 100 — hp 100 keeps
## the old hardness-1 feel, 300 the old hardness-3); the future tool-damage
## model consumes it per swing.
@export var hp: int = 100

## Time in minutes for a damaged voxel of this material to fully regenerate back
## to max HP. Default 0.25 min (15 seconds). Set to <= 0.0 to disable regeneration
## (e.g. asphalt, masonry).
@export var minutes_to_full_heal: float = 0.25

## What one completed dig of this material drops into the digger's inventory
## (the HarvestParams.yields shape).
@export var yields: Array[ItemAmount] = []

## Inclusive depth band in voxel rows below the PRISTINE generated surface
## (surface row = depth 0; F13 supplies the pristine height, stable under
## digging). Materials whose band contains the dig depth are strata
## candidates; depth above the surface (authored mounds) matches no band.
@export var min_depth: int = 0
@export var max_depth: int = 0x7FFFFFFF

## Approximate blocks per vein cluster -> TerrainStrata noise wavelength.
@export var vein_size: int = 8

## Relative frequency within the depth band, normalized across the band's
## candidates at query time. Any non-negative scale (10:2:1 reads as a mix
## ratio); 0 = never generates.
@export var spawn_weight: float = 1.0

## Triplanar band texture for the terrain shader's DEPTH-BAND look (F14
## fallback: shader rules only — there is no per-voxel rendering). Only band
## endpoints (the surface material and the dominant deep material) sample it;
## other materials are visually identified by their Decal marker `color`.
@export var texture: Texture2D = null

## Radius of the sphere one placement of this material adds (also the blob
## ghost's radius — the preview shows exactly the volume). Fixed size in v1,
## matching the dig tool's carve radius decision.
@export var place_radius: float = 1.5

## Palette icon (build menu). Optional — iconless materials fall back to the
## menu's default icon.
@export var icon: Texture2D = null
