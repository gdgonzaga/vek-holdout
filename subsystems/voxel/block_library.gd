extends Resource
class_name BlockLibrary
## Registry of block types. Maps string block_id <-> integer voxel-tool library
## index, and owns the VoxelBlockyLibrary the mesher renders with.
##
## Index convention (two tiers, see docs/VOXEL-TOOL-NOTES.md):
## - Base table: 0 is always air (VoxelBlockyModelEmpty); terrain is forced to
##   index 1 (what VoxelGeneratorFlat emits); the rest load alphabetically.
##   Stable order — saved maps store these indices, so inserting a block
##   .tres that sorts before an existing one re-orders the table and
##   invalidates saves.
## - Variant appendix: for defs with rotation_mode != NONE, one variant model
##   per orientation is baked AFTER the whole base table (sharing the def's
##   mesh, differing only in mesh_ortho_rotation_index). Base indices are
##   unaffected by variants, so maps saved before a def became rotatable keep
##   loading unchanged.
##
## Stored voxel values are always plain indices from this library — the mesher
## renders value N as model N. Rotation rides in WHICH index is stored, never
## in bits packed into the value (BlockyGrid.set_block resolves base+rotation
## to a variant index via get_stored_index()).

## Terrain must occupy index 1 because VoxelGeneratorFlat emits voxel_type = 1.
const TERRAIN_ID := "terrain"

## Overridable scan dir (tests point it at fixture .tres dirs).
var _blocks_dir := "res://data/blocks/"

var _defs_by_id: Dictionary = {}        # block_id (String) -> BlockDef
var _defs_by_index: Dictionary = {}     # int index -> BlockDef (base AND variant indices)
var _index_by_id: Dictionary = {}       # block_id (String) -> int base index
var _voxel_library: VoxelBlockyLibrary = null
var _next_index: int = 0  # next free library slot; 0 reserved for air
var _variant_index: Dictionary = {}     # Vector2i(base, ortho) -> int variant index
var _variant_info: Dictionary = {}      # int variant index -> Vector2i(base, ortho)

func _init(blocks_dir: String = "") -> void:
	if blocks_dir != "":
		_blocks_dir = blocks_dir
	_build()

## Load every BlockDef in the blocks dir and assemble the VoxelBlockyLibrary,
## baking rotation variants after the base table. Deterministic order:
## terrain first (-> index 1), then the rest alphabetically.
func _build() -> void:
	var paths := _scan_block_defs()
	paths.sort()

	_voxel_library = VoxelBlockyLibrary.new()
	# Index 0 = air.
	_voxel_library.add_model(VoxelBlockyModelEmpty.new())
	_next_index = 1

	# Terrain must be index 1 (matches VoxelGeneratorFlat voxel_type).
	var ordered: Array[String] = []
	var terrain_path := _blocks_dir + TERRAIN_ID + ".tres"
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
		# the blocks dir holds the baked VoxelBlockyLibrary alongside the
		# BlockDefs; only the latter are models we add to our own library. Skip
		# anything that isn't a BlockDef (a typed load would throw on the
		# baked library).
		var res = load(path)
		if not (res is BlockDef):
			continue
		var def: BlockDef = res
		var index := _add_base_model(def)
		_index_by_id[def.id] = index
		_defs_by_id[def.id] = def

	_bake_variants()

	_voxel_library.bake()

## The def's base model (unrotated). Index assignment is sequential and
## terrain-first — see the class doc's index convention.
func _add_base_model(def: BlockDef) -> int:
	# We track the next index ourselves rather than reading get_model_count():
	# the GDExtension return type isn't statically known to the parser, which
	# breaks := inference. Indexing is deterministic (0 = air, then sequential).
	var index := _next_index
	_next_index += 1
	_voxel_library.add_model(VoxelLibraryGenerator.create_block_model(def, 0))
	_defs_by_index[index] = def
	return index

## Bake one variant model per orientation for rotatable defs, appended after
## the whole base table. Slot 0 (identity) needs no variant — the base model
## already renders it.
func _bake_variants() -> void:
	var base_indices: Array = _index_by_id.values()
	base_indices.sort()
	for base_index: int in base_indices:
		var def: BlockDef = _defs_by_index[base_index]
		if def.rotation_mode == BlockDef.RotationMode.NONE:
			continue
		var orthos: Array[int] = []
		if def.rotation_mode == BlockDef.RotationMode.YAW_ONLY:
			orthos = BlockDef.YAW_INDICES.duplicate()
		else:
			for i in range(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS):
				orthos.append(i)
		for ortho: int in orthos:
			if ortho == 0:
				continue
			var variant := _next_index
			_next_index += 1
			_voxel_library.add_model(VoxelLibraryGenerator.create_block_model(def, ortho))
			_variant_index[Vector2i(base_index, ortho)] = variant
			_variant_info[variant] = Vector2i(base_index, ortho)
			_defs_by_index[variant] = def

func _scan_block_defs() -> PackedStringArray:
	var dir := DirAccess.open(_blocks_dir)
	if dir == null:
		push_error("BlockLibrary: cannot open %s" % _blocks_dir)
		return PackedStringArray()
	var out := PackedStringArray()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres") and name != "block_def.gd":
			out.append(_blocks_dir + name)
		name = dir.get_next()
	return out

# --- query surface ---

func get_def(block_id: String) -> BlockDef:
	return _defs_by_id.get(block_id)

## Def for a stored index — resolves variant indices to their owning def.
func get_def_by_index(index: int) -> BlockDef:
	return _defs_by_index.get(index)

func get_index(block_id: String) -> int:
	# Air is index 0; unknown -> -1.
	if block_id == "":
		return 0
	return _index_by_id.get(block_id, -1)

## Inverse: stored index -> block_id (0 -> ""). Variant indices resolve to
## their def's id.
func get_id(index: int) -> String:
	var def: BlockDef = _defs_by_index.get(index)
	return def.id if def != null else ""

func has_id(block_id: String) -> bool:
	return _defs_by_id.has(block_id)

func get_all_defs() -> Array:
	return _defs_by_id.values()

## Sorted list of base block indices in the library (excluding air 0 and variant appendix).
func get_base_indices() -> Array[int]:
	var indices: Array[int] = []
	for idx in _index_by_id.values():
		indices.append(idx)
	indices.sort()
	return indices

## True if the given stored/library index is a base block index.
func is_base_index(index: int) -> bool:
	return index > 0 and get_base_index(index) == index

func get_voxel_library() -> VoxelBlockyLibrary:
	return _voxel_library

# --- rotation variant resolution ---------------------------------------------

## The renderable stored index for placing `base_index` at `rot_index`
## (an orthogonal orientation index, 0..23). Sanitizes the rotation against
## the def's rotation_mode and resolves to a baked variant; rotation 0 (and
## any rotation on a NONE def, or an unknown base) stores the base index
## itself.
func get_stored_index(base_index: int, rot_index: int) -> int:
	var def: BlockDef = _defs_by_index.get(base_index)
	if def == null:
		return base_index
	var sanitized: int = def.sanitize_rotation(rot_index)
	if sanitized == 0:
		return base_index
	return _variant_index.get(Vector2i(base_index, sanitized), base_index)

## The def's base index for a stored index (variant indices map to their
## owner's base; everything else passes through — including values outside
## this library, which callers treat defensively).
func get_base_index(stored_index: int) -> int:
	var info: Vector2i = _variant_info.get(stored_index, Vector2i(stored_index, 0))
	return info.x

## The orthogonal orientation (0..23) a stored index renders at. 0 for base
## indices and unknown values.
func get_rotation_index(stored_index: int) -> int:
	var info: Vector2i = _variant_info.get(stored_index, Vector2i(stored_index, 0))
	return info.y
