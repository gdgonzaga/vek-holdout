extends Node
## Global catalog of all loadable maps. Read-only after _ready.
##
## Registered as an autoload so SceneManager / ExpeditionManager can look up map
## scenes by id without reference-passing. Mirrors the silent-null DirAccess form
## used by build_library.gd (NOT block_library.gd's push_error): data/maps/ may
## not exist yet on a fresh checkout, and that's fine.

const _DIR := "res://data/maps/"

var _defs_by_id: Dictionary = {}


func _ready() -> void:
	var dir := DirAccess.open(_DIR)
	if dir == null:
		return                                 # data/maps/ may not exist yet
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var def: MapDef = load(_DIR + fname)
			if def != null and def.id != "":
				_defs_by_id[def.id] = def
		fname = dir.get_next()


func get_def(id: String) -> MapDef:
	return _defs_by_id.get(id)


func has_def(id: String) -> bool:
	return _defs_by_id.has(id)


func get_all() -> Array:
	return _defs_by_id.values()


func get_maps_by_type(type: int) -> Array:
	var out: Array = []
	for def in _defs_by_id.values():
		if (def as MapDef).map_type == type:
			out.append(def)
	return out
