extends Node
## Global catalog of all loadable maps. Read-only after _ready.
##
## Registered as an autoload so SceneManager / ExpeditionManager can look up map
## scenes by id without reference-passing. Scans data/maps/<name>/map_def.tres for
## each map subdirectory. Mirrors the silent-null DirAccess form used by
## build_library.gd: data/maps/ may not exist yet, and that's fine.

const _DIR := "res://data/maps/"

var _defs_by_id: Dictionary = {}


func _ready() -> void:
	var dir := DirAccess.open(_DIR)
	if dir == null:
		return                                 # data/maps/ may not exist yet
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and not fname.begins_with("."):
			var def: MapDef = load(_DIR + fname + "/map_def.tres") as MapDef
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
