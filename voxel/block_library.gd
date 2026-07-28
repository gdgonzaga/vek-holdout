extends Resource
class_name BlockLibrary
## Registry of block types. Maps string block_id <-> integer voxel-tool library
## index, and owns the VoxelBlockyLibrary the mesher renders with.
##
## Index convention: 0 is always air (VoxelBlockyModelEmpty). Each BlockDef then
## gets the next index in load order. Terrain is forced to index 1 so that
## VoxelGeneratorFlat (which emits voxel_type = 1) renders as terrain without the
## VoxelGrid having to remap generator output.

const _DIR := "res://data/blocks/"

## Terrain must occupy index 1 because VoxelGeneratorFlat emits voxel_type = 1.
const TERRAIN_ID := "terrain"

var _defs_by_id: Dictionary = {}        # block_id (String) -> BlockDef
var _defs_by_index: Dictionary = {}     # int index -> BlockDef
var _index_by_id: Dictionary = {}       # block_id (String) -> int index
var _voxel_library: VoxelBlockyLibrary = null
var _next_index: int = 0  # next free library slot; 0 reserved for air

func _init() -> void:
	_build()

## Load every BlockDef in data/blocks/ and assemble the VoxelBlockyLibrary.
## Deterministic order: terrain first (-> index 1), then the rest alphabetically.
func _build() -> void:
	var paths := _scan_block_defs()
	paths.sort()

	_voxel_library = VoxelBlockyLibrary.new()
	# Index 0 = air.
	_voxel_library.add_model(VoxelBlockyModelEmpty.new())
	_next_index = 1

	# Terrain must be index 1 (matches VoxelGeneratorFlat voxel_type).
	var ordered: Array[String] = []
	var terrain_path := _DIR + TERRAIN_ID + ".tres"
	var has_terrain := false
	for p in paths:
		if p == terrain_path:
			has_terrain = true
			break
	if has_terrain:
		ordered.append(terrain_path)
	for p in paths:
		if p != terrain_path:
			ordered.append(p)

	for path in ordered:
		var def: BlockDef = load(path)
		if def == null:
			push_error("BlockLibrary: failed to load %s" % path)
			continue
		var index := _add_model_for(def)
		_index_by_id[def.block_id] = index
		_defs_by_id[def.block_id] = def
		_defs_by_index[index] = def

	_voxel_library.bake()

## Add this def's mesh as a VoxelBlockyModelMesh and return its assigned index.
func _add_model_for(def: BlockDef) -> int:
	var model := VoxelBlockyModelMesh.new()
	model.mesh = def.mesh
	# Collision generation property name varies across voxel_tool versions.
	if "collision_enabled_0" in model:
		model.set("collision_enabled_0", true)
	# We track the next index ourselves rather than reading get_model_count():
	# the GDExtension return type isn't statically known to the parser, which
	# breaks := inference. Indexing is deterministic (0 = air, then sequential).
	var index := _next_index
	_next_index += 1
	_voxel_library.add_model(model)
	return index

func _scan_block_defs() -> PackedStringArray:
	var dir := DirAccess.open(_DIR)
	if dir == null:
		push_error("BlockLibrary: cannot open %s" % _DIR)
		return PackedStringArray()
	var out := PackedStringArray()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres") and name != "block_def.gd":
			out.append(_DIR + name)
		name = dir.get_next()
	return out

# --- query surface ---

func get_def(block_id: String) -> BlockDef:
	return _defs_by_id.get(block_id)

func get_def_by_index(index: int) -> BlockDef:
	return _defs_by_index.get(index)

func get_index(block_id: String) -> int:
	# Air is index 0; unknown -> -1.
	if block_id == "":
		return 0
	return _index_by_id.get(block_id, -1)

func get_id(index: int) -> String:
	# Index 0 = air = empty string.
	if index == 0:
		return ""
	var def: BlockDef = _defs_by_index.get(index)
	return def.block_id if def != null else ""

func has_id(block_id: String) -> bool:
	return _defs_by_id.has(block_id)

func get_all_defs() -> Array:
	return _defs_by_id.values()

func get_voxel_library() -> VoxelBlockyLibrary:
	return _voxel_library
