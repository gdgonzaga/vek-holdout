extends Node
## Global catalog of item definitions loaded from data/items/.
## The item_id is the ItemDef.id field (e.g. "wood_block"), matching the
## Map/Block/Build libraries.
##
## Read-only after _ready. Register as an autoload.

const _DIR := "res://data/items/"

var _defs_by_id: Dictionary = {} # item_id (String) -> ItemDef


func _ready() -> void:
	_load_dir(_DIR)


func _load_dir(dir_path: String) -> void:
	var loaded := ContentDirLoader.load_by_id(dir_path, func(res: Variant) -> bool: return res is ItemDef)
	_defs_by_id.merge(loaded, true)


func get_def(item_id: String) -> ItemDef:
	return _defs_by_id.get(item_id)


## Player-facing name for an item id: its def's display name, or the raw id when
## the def no longer exists (an orphaned stack, a removed item), never "".
func get_display_name(item_id: String) -> String:
	var def: ItemDef = get_def(item_id)
	return def.get_display_name() if def != null else item_id


func has_def(item_id: String) -> bool:
	return _defs_by_id.has(item_id)


func get_all_defs() -> Array[ItemDef]:
	var result: Array[ItemDef] = []
	for def in _defs_by_id.values():
		if def is ItemDef:
			result.append(def)
	return result


func get_all_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _defs_by_id.keys():
		result.append(str(key))
	return result
