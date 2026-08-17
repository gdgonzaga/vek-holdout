extends Resource
class_name TerrainGenDef
## Parameters for the natural (smooth) terrain generator — the data half of the
## dual-voxel conversion (docs/TODO.md "Dual-voxel conversion", D2/D4).
##
## A MapDef with `terrain_gen` set gets a SmoothGrid whose VoxelGeneratorNoise2D
## is built from these values; null means the map has no smooth terrain at all
## and plays exactly as before. Schema: docs/architecture/data-schemas.md.
##
## F8 (docs/VOXEL-TOOL-NOTES.md) is the authority on what the generator accepts:
## `noise`, `height_start`, `height_range` — verified property names in this
## addon build.

@export var id: String
@export var display_name: String

## FastNoiseLite seed for the heightfield. Same seed + frequency = same hills,
## which is what makes sqlite-persisted edits reproducible across loads.
## Frequency is also the slope budget: max slope ≈ height_range·π·frequency,
## which must stay under max_walk_slope_deg's tangent or the noise itself
## creates unwalkable hills (the 50 m default pairs range 50 with 0.005 → ~38°).
@export var noise_seed: int = 0
@export var noise_frequency: float = 0.012

## Lowest terrain height and how far above it the noise lifts the surface
## (VoxelGeneratorNoise2D's own naming, kept 1:1 to avoid a translation layer).
@export var height_start: float = -4.0
@export var height_range: float = 12.0

## D4 slope gate for walkability/pathing on the smooth surface, in degrees.
## Kept <= 45 so a 1 m horizontal step changes height by <= 1 cell and the
## derived stand-cell lattice never demands a climb above the step model
## (voxel_pathfinder.gd: climb +1). Consumed in Phase 3.
@export var max_walk_slope_deg: float = 45.0
