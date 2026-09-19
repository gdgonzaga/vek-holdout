class_name ContentDirLoader
extends RefCounted
## Shared content-directory scanning for the id-keyed data registries (ItemDB,
## EnemyLibrary, CropLibrary, ColonistNeeds, BuildLibrary, BlockLibrary).
## Recurses into subdirectories so a category's data/<category>/ folder can be
## split into nested subfolders as it grows, without any loader-side changes —
## identity is the `id` field, never the path (see data-schemas.md).


# =================
# Primary Functions
# =================

## Every file under dir_path (recursing into subdirectories) whose name ends
## in extension. Missing dir_path returns an empty array — callers treat an
## unauthored category folder as fine, not an error.
static func find_resource_paths(dir_path: String, extension: String = ".tres") -> PackedStringArray:
	var out := PackedStringArray()
	# 1. Recursive Path Collection: Walk dir_path top-down, appending every matching file path.
	_scan_paths(dir_path, extension, out)
	return out


## Recursively loads every extension resource under dir_path passing
## is_valid_type, indexed by each resource's `id` field. A resource with an
## empty id is skipped with a warning rather than dropped silently.
static func load_by_id(dir_path: String, is_valid_type: Callable, extension: String = ".tres") -> Dictionary:
	var out: Dictionary = {}
	# 1. Path Discovery: Recursively collect every candidate resource path under dir_path.
	var paths := find_resource_paths(dir_path, extension)
	for path: String in paths:
		# 2. Typed Registration: Load, type-check, and index the candidate at path by id.
		_register_by_id(path, is_valid_type, out)
	return out


# ===================
# Auxiliary Functions
# ===================

static func _scan_paths(dir_path: String, extension: String, out: PackedStringArray) -> void:
	## Auxiliary: Appends matching file paths under dir_path, recursing into non-hidden subdirectories.
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full_path := dir_path.path_join(fname)
			if dir.current_is_dir():
				_scan_paths(full_path, extension, out)
			elif fname.ends_with(extension):
				out.append(full_path)
		fname = dir.get_next()
	dir.list_dir_end()


static func _register_by_id(path: String, is_valid_type: Callable, out: Dictionary) -> void:
	## Auxiliary: Loads the resource at path and, if type-valid with a non-empty id, indexes it.
	var res: Resource = load(path)
	if not is_valid_type.call(res):
		return
	if not ("id" in res) or str(res.id) == "":
		push_warning("ContentDirLoader: resource at %s has empty id; skipping" % path)
		return
	out[res.id] = res
