extends Node
## Global catalog of enemy definitions loaded from data/enemies/.
## The enemy_id is the EnemyDef.id field (e.g. "enemy_swarmer"), matching the
## Item/Block/Build/Map libraries.
##
## Read-only after _ready. Register as an autoload.

const _DIR := "res://data/enemies/"

var _defs_by_id: Dictionary = {} # enemy_id (String) -> EnemyDef


func _ready() -> void:
	_load_dir(_DIR)


func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res = load(dir_path + fname)
			if res is EnemyDef:
				if res.id == "":
					push_warning("EnemyDef at %s has empty id; skipping" % (dir_path + fname))
				else:
					_defs_by_id[res.id] = res
		fname = dir.get_next()


func get_def(enemy_id: String) -> EnemyDef:
	return _defs_by_id.get(enemy_id)


func has_def(enemy_id: String) -> bool:
	return _defs_by_id.has(enemy_id)


func get_all_defs() -> Array[EnemyDef]:
	var result: Array[EnemyDef] = []
	for def in _defs_by_id.values():
		if def is EnemyDef:
			result.append(def)
	return result


func get_all_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _defs_by_id.keys():
		result.append(str(key))
	return result
