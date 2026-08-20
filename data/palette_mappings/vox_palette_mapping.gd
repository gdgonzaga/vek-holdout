class_name VoxPaletteMapping
extends Resource
## Maps MagicaVoxel palette entries to game block IDs, smooth terrain materials, air, or ignored voxels.

## Unique identifier matching the resource filename.
@export var id: String = ""

## User-facing display name shown in editor tooling.
@export var display_name: String = ""

## List of palette entry mappings.
@export var entries: Array[VoxPaletteEntry] = []


## Look up the mapping entry for a given palette index and optional hex color.
## Matches primarily by source_index. If no matching index is found and hex is non-empty,
## falls back to matching by source_hex (case-insensitive, ignoring leading '#').
func get_target_for_index(index: int, hex: String = "") -> VoxPaletteEntry:
	for entry in entries:
		if entry != null and entry.source_index == index and index >= 0:
			return entry
	if not hex.is_empty():
		var clean_hex := hex.strip_edges().trim_prefix("#").to_upper()
		for entry in entries:
			if entry != null and not entry.source_hex.is_empty():
				var entry_hex := entry.source_hex.strip_edges().trim_prefix("#").to_upper()
				if entry_hex == clean_hex:
					return entry
	return null
