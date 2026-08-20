class_name StructureDef
extends Resource
## Definition of an importable voxel structure authored in MagicaVoxel (.vox).

enum PivotAnchor {
	BOTTOM_CENTER,
	BOTTOM_CORNER,
	GEOMETRIC_CENTER,
	CUSTOM,
}

## Unique identifier matching the resource filename (data conventions).
@export var id: String = ""

## User-facing display name shown in the structure browser.
@export var display_name: String = ""

## Category group for filtering in the structure browser (e.g. "Buildings", "Decorations", "Ruins").
@export var category: String = "General"

## Path to the .vox file (e.g. "res://data/structures/vox/cottage.vox" or filesystem path).
@export var vox_file_path: String = ""

## Palette mapping resource used to interpret voxel colors in the .vox file.
@export var palette_mapping: VoxPaletteMapping = null

## Anchor mode used to calculate the placement pivot offset.
@export var pivot_anchor: PivotAnchor = PivotAnchor.BOTTOM_CENTER

## Offset applied when pivot_anchor is CUSTOM (or added to base anchor).
@export var custom_pivot_offset: Vector3i = Vector3i.ZERO

## Dimensions of the structure bounding box in voxels (computed on parse or cached).
@export var bounding_box_size: Vector3i = Vector3i.ZERO
