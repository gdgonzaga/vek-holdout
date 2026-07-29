extends Node
## Global catalog of everything the player can build (ARCH: build subsystem).
## Loaded from data/blocks/ (BlockDef) and data/buildables/ (future furniture).
##
## Registered as an autoload so the build menu / BuildController can read it
## across scenes without reference-passing. Read-only after _ready (the catalog
## doesn't change at runtime — unlock *availability* is a separate concern, see
## get_unlocked()).

const _DIR_BLOCKS := "res://data/blocks/"
const _DIR_BUILDABLES := "res://data/buildables/"

var _defs_by_id: Dictionary = {}   # id (String) -> BuildableDef


func _ready() -> void:
	_load_dir(_DIR_BLOCKS)
	_load_dir(_DIR_BUILDABLES)


## Load every .tres in a directory as a BuildableDef, keyed by id.
func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return   # not all folders exist yet (e.g. furniture); fine
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var def: BuildableDef = load(dir_path + fname)
			if def != null and def.id != "":
				_defs_by_id[def.id] = def
		fname = dir.get_next()


## The buildables the player can currently choose. STUB: returns every def with
## unlocked_by_default == true. TODO: route through RunProgress (earned unlocks)
## when that autoload exists — this method's signature stays the same, so the
## build menu never needs to change.
func get_unlocked() -> Array:
	var out: Array = []
	for def in _defs_by_id.values():
		if def.unlocked_by_default:
			out.append(def)
	return out


func get_def(id: String) -> BuildableDef:
	return _defs_by_id.get(id)


func has_def(id: String) -> bool:
	return _defs_by_id.has(id)
