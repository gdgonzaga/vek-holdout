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
## F8/F11 remain the MESHER ceiling — the terrain has one visual look per map —
## so unlike BlockDef there is no mesh/material here; `texture` is reserved
## data, not a render hook. Equipment gating (later) matches on `id`.

@export var id: String
@export var display_name: String

## Break pool. Today it scales dig time (work_time * hp / 100 — hp 100 keeps
## the old hardness-1 feel, 300 the old hardness-3); the future tool-damage
## model consumes it per swing.
@export var hp: int = 100

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

## Reserved (F8/F11 ceiling): NOT rendered on the terrain in v1 — future
## dig-UI feedback swatch and per-material visuals if a custom mesher lands.
@export var texture: Texture2D = null

## Radius of the sphere one placement of this material adds (also the blob
## ghost's radius — the preview shows exactly the volume). Fixed size in v1,
## matching the dig tool's carve radius decision.
@export var place_radius: float = 1.5

## Palette icon (build menu). Optional — iconless materials fall back to the
## menu's default icon.
@export var icon: Texture2D = null
