extends Node
## Global catalog of everything the player can build (ARCH: build subsystem).
## Loaded from data/blocks/ (BlockDef), data/buildables/ (BuildableDef), and
## data/furniture/ (FurnitureDef).
##
## Registered as an autoload so the build menu / BuildController can read it
## across scenes without reference-passing. Read-only after _ready (the catalog
## doesn't change at runtime — the defs are session-stable content).
##
## "What's unlocked" is delegated to RunProgress (the run-state autoload). This
## catalog seeds RunProgress with the unlocked-by-default defs at startup and on
## run_started (New Game). It does NOT re-read data on run_started — it walks the
## already-loaded _defs_by_id.

const _DIR_BLOCKS := "res://data/blocks/"
const _DIR_BUILDABLES := "res://data/buildables/"
const _DIR_FURNITURE := "res://data/furniture/"

## Sentinel id for the Deconstruct tool entry. It is not a BuildableDef (no mesh,
## cost, or placeable target) — selecting it routes LMB to removal instead of
## placement. get_def() returns null for it, so existing lookups fail safe.
const DECONSTRUCT_ID := "__deconstruct__"


## True for the Deconstruct tool id. Static so callers don't need an instance.
static func is_deconstruct(id: String) -> bool:
	return id == DECONSTRUCT_ID

var _defs_by_id: Dictionary = {}   # id (String) -> BuildableDef


func _ready() -> void:
	_load_dir(_DIR_BLOCKS)
	_load_dir(_DIR_BUILDABLES)
	_load_dir(_DIR_FURNITURE)   # FurnitureDef (loaded as BuildableDef — polymorphic)
	# Seed the default-unlocked buildables into RunProgress. Done at startup (first
	# run) AND on run_started (New Game: RunProgress was reset, re-add defaults
	# without re-reading the data). Additive + idempotent, so order is irrelevant.
	_seed_defaults()
	EventBus.run_started.connect(_seed_defaults)


## Load every .tres in a directory as a BuildableDef, keyed by id.
func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return   # not all folders exist yet (e.g. furniture); fine
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			# Untyped load + `is` check: data/blocks/ also holds non-def resources
			# (the baked VoxelBlockyLibrary from bake_voxel_library.gd). A typed
			# assignment would throw on those, so filter by actual runtime type.
			var res = load(dir_path + fname)
			if res is BuildableDef and res.id != "":
				_defs_by_id[res.id] = res
		fname = dir.get_next()


## Push every unlocked_by_default def into RunProgress. No disk re-read — walks
## the in-memory catalog. Idempotent (RunProgress.unlock is a no-op if present).
func _seed_defaults() -> void:
	for def in _defs_by_id.values():
		if def.unlocked_by_default:
			RunProgress.unlock(def.id)


## Is this buildable currently available? Defaults + earned unlocks both flow
## through RunProgress (it holds both, since defaults are seeded into it).
func is_unlocked(id: String) -> bool:
	return RunProgress.is_unlocked(id)


## The buildables the player can currently choose (for the build menu).
func get_unlocked() -> Array:
	var out: Array = []
	for def in _defs_by_id.values():
		if RunProgress.is_unlocked(def.id):
			out.append(def)
	return out


## Earn an unlock at runtime (items/skills/quests call this). Thin pass-through
## to RunProgress so callers talk to the catalog, not run-state internals.
func unlock(id: String) -> void:
	RunProgress.unlock(id)


func get_def(id: String) -> BuildableDef:
	return _defs_by_id.get(id)


func has_def(id: String) -> bool:
	return _defs_by_id.has(id)


## All defs in the catalog (for editor tooling — ignores unlock status).
func get_all_defs() -> Array[BuildableDef]:
	var out: Array[BuildableDef] = []
	for def in _defs_by_id.values():
		out.append(def)
	return out
