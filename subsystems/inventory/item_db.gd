extends Node
## Global catalog of item definitions loaded from data/items/.
## The item_id is the .tres filename (e.g. "wood" from "wood.tres").
##
## Read-only after _ready. Register as an autoload.

const _DIR := "res://data/items/"

var _defs_by_id: Dictionary = {} # item_id (String) -> ItemDef


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
			if res is ItemDef:
				var item_id := fname.get_basename()
				_defs_by_id[item_id] = res
		fname = dir.get_next()


func get_def(item_id: String) -> ItemDef:
	return _defs_by_id.get(item_id)


func has_def(item_id: String) -> bool:
	return _defs_by_id.has(item_id)
