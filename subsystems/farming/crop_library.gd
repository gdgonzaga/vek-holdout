class_name CropLibrary
extends RefCounted
## Global registry and loader for CropDefs (ARCH "Farming", data/crops/).
## Static helper class to access available crops without autoload overhead.

const _DIR := "res://data/crops/"

static var _crops_by_id: Dictionary = {} # id (String) -> CropDef
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res = load(_DIR + fname)
			if res is CropDef and res.id != "":
				_crops_by_id[res.id] = res
		fname = dir.get_next()


static func get_crop(id: String) -> CropDef:
	_ensure_loaded()
	return _crops_by_id.get(id)


static func has_crop(id: String) -> bool:
	_ensure_loaded()
	return _crops_by_id.has(id)


static func get_all_crops() -> Array[CropDef]:
	_ensure_loaded()
	var out: Array[CropDef] = []
	for crop in _crops_by_id.values():
		out.append(crop)
	return out


static func reload() -> void:
	_crops_by_id.clear()
	_loaded = false
	_ensure_loaded()
