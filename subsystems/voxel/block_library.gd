extends Resource
class_name BlockLibrary
## Registry of block types. Maps string block_id <-> integer voxel-tool library
## index, and owns the VoxelBlockyLibrary the mesher renders with.
##
## Index convention (two tiers, see docs/VOXEL-TOOL-NOTES.md):
## - Base table: 0 is always air (VoxelBlockyModelEmpty); the rest load
##   alphabetically. Stable order — saved maps store these indices, so
##   inserting a block .tres that sorts before an existing one re-orders the
##   table and invalidates saves.
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

## Preserved index order for shipped baseline blocks to guarantee save format compatibility.
const LEGACY_BLOCK_ORDER: Array[String] = [
	"full_block_wood",
	"half_block_wood",
	"metal",
	"quarter_block_wood",
	"reinforced",
	"scrap",
	"stairs_corner_left_wood",
	"stairs_corner_right_wood",
	"stairs_wood",
	"stone",
	"wedge_corner_left_wood",
	"wedge_corner_right_wood",
	"wedge_wood",
]


## Load every BlockDef in the blocks dir and assemble the VoxelBlockyLibrary,
## baking rotation variants after the base table. Stable registry order guarantees
## that newly added blocks do not shift existing indices in saved maps.
func _build() -> void:
	# 1. Block Scanning: Discover all valid BlockDef resources in the configured blocks directory.
	var defs: Array[BlockDef] = _load_scanned_block_defs()

	# 2. Stable Ordering: Order BlockDef resources according to locked registry invariants.
	_sort_block_defs_stably(defs)

	_voxel_library = VoxelBlockyLibrary.new()
	# Index 0 = air.
	_voxel_library.add_model(VoxelBlockyModelEmpty.new())
	_next_index = 1

	for def in defs:
		# 3. Model Registration: Register the base unrotated model into the VoxelBlockyLibrary.
		var index := _add_base_model(def)
		_index_by_id[def.id] = index
		_defs_by_id[def.id] = def

	# 4. Variant Baking: Append rotation variants after the base table.
	_bake_variants()

	_voxel_library.bake()


func _load_scanned_block_defs() -> Array[BlockDef]:
	## Auxiliary: Loads all BlockDef resources found in the target directory.
	var paths := _scan_block_defs()
	var defs: Array[BlockDef] = []
	for path in paths:
		var res = load(path)
		if res is BlockDef:
			defs.append(res as BlockDef)
	return defs


func _sort_block_defs_stably(defs: Array[BlockDef]) -> void:
	## Auxiliary: Sorts block definitions by explicit fixed index, legacy baseline order, or filename.
	defs.sort_custom(func(a: BlockDef, b: BlockDef) -> bool:
		var rank_a := _get_block_sort_rank(a)
		var rank_b := _get_block_sort_rank(b)
		if rank_a != rank_b:
			return rank_a < rank_b
		return a.resource_path < b.resource_path
	)


func _get_block_sort_rank(def: BlockDef) -> int:
	## Auxiliary: Resolves sort priority rank for a block definition.
	if def.fixed_index > 0:
		return def.fixed_index
	var legacy_idx := LEGACY_BLOCK_ORDER.find(def.id)
	if legacy_idx >= 0:
		return legacy_idx + 1
	return 100000


## The def's base model (unrotated). Index assignment is sequential — see the
## class doc's index convention.
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
	if DirAccess.open(_blocks_dir) == null:
		push_error("BlockLibrary: cannot open %s" % _blocks_dir)
		return PackedStringArray()
	return ContentDirLoader.find_resource_paths(_blocks_dir)

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


## True if the block at the given stored/library index is a fluid (e.g. water).
func is_fluid(index: int) -> bool:
	var def: BlockDef = get_def_by_index(index)
	return def != null and def.is_fluid


## True if the block at the given stored/library index is water.
func is_water(index: int) -> bool:
	var def: BlockDef = get_def_by_index(index)
	return def != null and def.id == "water"


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
