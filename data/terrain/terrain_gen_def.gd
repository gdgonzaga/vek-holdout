extends Resource
class_name TerrainGenDef
## Parameters for the natural (smooth) terrain generator — the data half of the
## dual-voxel conversion (docs/TODO.md "Dual-voxel conversion", D2/D4).
##
## A MapDef with `terrain_gen` set gets a SmoothGrid whose generator is built
## from these values — noise by default, or a grayscale heightmap image when
## `heightmap` is set; null means the map has no smooth terrain at all and plays
## exactly as before. Schema: docs/architecture/data-schemas.md.
##
## F8 (docs/VOXEL-TOOL-NOTES.md) is the authority on what the generator accepts:
## `noise`, `height_start`, `height_range` — verified property names in this
## addon build (plus `image` on VoxelGeneratorImage, probed in
## tmp/heightmap_gen_probe.gd).

@export var id: String
@export var display_name: String

## FastNoiseLite seed for the heightfield. Same seed + frequency = same hills,
## which is what makes sqlite-persisted edits reproducible across loads.
## Frequency is also the slope budget: max slope ≈ height_range·π·frequency,
## which must stay under max_walk_slope_deg's tangent or the noise itself
## creates unwalkable hills (the 50 m default pairs range 50 with 0.005 → ~38°).
@export var noise_seed: int = 0
@export var noise_frequency: float = 0.012

## Optional grayscale image driving generation instead of noise — the
## external-tool authoring path (Krita/GIMP heightmaps). Pixel brightness 0..1
## maps across height_start..height_start+height_range; one pixel = one world
## meter, image origin = world origin. Null = noise path. PNGs placed under
## data/terrain/ must use Lossless import (VRAM compression destroys the pixel
## data get_image() returns); the map editor embeds an ImageTexture instead,
## which satisfies the same field.
@export var heightmap: Texture2D = null

## Lowest terrain height and how far above it the surface lifts — shared by
## both generator paths (VoxelGeneratorNoise2D / VoxelGeneratorImage naming,
## kept 1:1 to avoid a translation layer).
@export var height_start: float = -4.0
@export var height_range: float = 12.0

## D4 slope gate for walkability/pathing on the smooth surface, in degrees.
## Kept <= 45 so a 1 m horizontal step changes height by <= 1 cell and the
## derived stand-cell lattice never demands a climb above the step model
## (voxel_pathfinder.gd: climb +1). Consumed in Phase 3.
@export var max_walk_slope_deg: float = 45.0
