class_name EditorContentLoader
extends RefCounted
## Palette content for the map editor. Scans recurse (ContentDirLoader) because
## data/furniture/ is split into category subfolders; identity is the id field,
## never the path (AGENTS.md "Data conventions").

const FURNITURE_DIR: String = "res://data/furniture/"
const STRUCTURE_DIR: String = "res://data/structures/"


# =================
# Primary Functions
# =================

static func load_furniture_defs(dir_path: String = FURNITURE_DIR) -> Array[FurnitureDef]:
	var out: Array[FurnitureDef] = []
	# 1. Recursive discovery: every .tres under the folder tree, category subfolders included.
	for path: String in ContentDirLoader.find_resource_paths(dir_path):
		# 2. Type filter: only FurnitureDef is placeable as authored furniture; flora defs share the folder.
		_append_if_furniture(path, out)
	# 3. Stable order: by id so the palette does not shuffle between runs.
	out.sort_custom(_furniture_before)
	return out


static func load_structure_defs(dir_path: String = STRUCTURE_DIR) -> Array[StructureDef]:
	var out: Array[StructureDef] = []
	var paths := ContentDirLoader.find_resource_paths(dir_path, ".tres")
	paths.append_array(ContentDirLoader.find_resource_paths(dir_path, ".res"))
	for path: String in paths:
		# 1. Type filter: only StructureDef is placeable as authored structures.
		_append_if_structure(path, out)
	# 2. Stable order: by display name, falling back to id.
	out.sort_custom(_structure_before)
	return out


# ===================
# Auxiliary Functions
# ===================

static func _append_if_furniture(path: String, out: Array[FurnitureDef]) -> void:
	## Auxiliary: loads path and keeps it when it is a FurnitureDef.
	var res: Resource = load(path)
	if res is FurnitureDef:
		out.append(res as FurnitureDef)


static func _append_if_structure(path: String, out: Array[StructureDef]) -> void:
	## Auxiliary: loads path and keeps it when it is a StructureDef.
	var res: Resource = load(path)
	if res is StructureDef:
		out.append(res as StructureDef)


static func _furniture_before(a: FurnitureDef, b: FurnitureDef) -> bool:
	## Auxiliary: comparison comparator for sorting furniture by id.
	return a.id < b.id


static func _structure_before(a: StructureDef, b: StructureDef) -> bool:
	## Auxiliary: comparison comparator for sorting structures by display_name or id.
	var name_a := a.display_name if not a.display_name.is_empty() else a.id
	var name_b := b.display_name if not b.display_name.is_empty() else b.id
	return name_a < name_b
