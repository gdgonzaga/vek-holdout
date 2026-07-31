@tool
extends EditorScript
## One-shot bake of the assembled VoxelBlockyLibrary to
## data/blocks/voxel_library.tres.
##
## The library is the decisive render ingredient for in-editor authoring (Fact 5
## of tmp/map_authoring/IMPLEMENTATION.md): without it the editor viewport is
## blank even when the generator/mesher are correctly wired. The base world
## wires the library in code at _ready (VoxelGrid._ready), which works at
## runtime, but authored .tscn scenes need it baked into the mesher so painted
## voxels render in the editor without the plugin active.
##
## Run from the editor: File menu -> Run (or the EditorScript "Run" button) with
## this script open. It is safe to re-run: output is deterministic and the file
## is overwritten in place.
##
## Result: res://data/blocks/voxel_library.tres — a VoxelBlockyLibrary with 7
## models (0 air + 6 blocks). Index table is stable (see BlockLibrary docs):
##   0 air, 1 terrain, 2 metal, 3 reinforced, 4 scrap, 5 stone, 6 wood.

const _OUTPUT_PATH := "res://data/blocks/voxel_library.tres"


func _run() -> void:
	var lib := BlockLibrary.new()
	var voxel_lib: VoxelBlockyLibrary = lib.get_voxel_library()
	if voxel_lib == null:
		push_error("bake_voxel_library: BlockLibrary produced no VoxelBlockyLibrary (check data/blocks/*.tres)")
		return
	var err := ResourceSaver.save(voxel_lib, _OUTPUT_PATH)
	if err != OK:
		push_error("bake_voxel_library: ResourceSaver failed (%d) for %s" % [err, _OUTPUT_PATH])
		return
	print("bake_voxel_library: wrote %s (%d models)" % [_OUTPUT_PATH, voxel_lib.get_model_count()])
