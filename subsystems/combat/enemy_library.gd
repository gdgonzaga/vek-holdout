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
	var loaded := ContentDirLoader.load_by_id(dir_path, func(res: Variant) -> bool: return res is EnemyDef)
	_defs_by_id.merge(loaded, true)


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
