class_name VoxPaletteEntry
extends Resource
## Entry in a VoxPaletteMapping resource specifying how a MagicaVoxel palette
## index or hex color maps to game voxel types (BlockDef block_id or smooth terrain material).

enum TargetType {
	BLOCK,
	SMOOTH_TERRAIN,
	AIR,
	IGNORE,
}

## 1-based palette index in MagicaVoxel (.vox palette indices are 1-256).
@export var source_index: int = -1

## Optional hex string (e.g. "#FF00AA" or "FF00AA") for matching by color.
@export var source_hex: String = ""

## Destination target type when stamped into the voxel world.
@export var target_type: TargetType = TargetType.BLOCK

## BlockDef id (e.g. "stone_wall", "wood_planks") if target_type is TargetType.BLOCK.
@export var block_id: String = ""

## TerrainMaterialDef id (e.g. "ground") if target_type is TargetType.SMOOTH_TERRAIN.
## Empty = the smooth grid's default_material.
@export var terrain_material_id: String = ""
