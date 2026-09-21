extends RefCounted
## In-memory BuildableDefs and TerrainMaterialDefs registered in BuildLibrary for one test and
## restored afterwards. Only the ids a test touches are restored, so registering
## "test_station" cannot disturb the rest of the autoload. Use instead of reading shipped
## blueprints or terrain materials.
##
## Usage:
##   const BuildLibrarySandbox = preload("res://test/helpers/build_library_sandbox.gd")
##   var _builds: BuildLibrarySandbox
##   _builds = BuildLibrarySandbox.new(self)     # in before_test
##   _builds.add_buildable(def)
##   _builds.restore()                           # in after_test

var _suite: GdUnitTestSuite
var _previous_buildables: Dictionary = {}  # id -> BuildableDef, or null when the id was not registered
var _previous_materials: Dictionary = {}   # id -> TerrainMaterialDef, or null when the id was not registered


func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite


# =================
# Primary Functions
# =================

## Registers `def` under def.id in BuildLibrary's buildable catalog.
func add_buildable(def: BuildableDef) -> BuildableDef:
	# 1. Snapshot: first registration of an id records what was there so restore() can undo it.
	_remember(_previous_buildables, BuildLibrary._defs_by_id, def.id)
	BuildLibrary._defs_by_id[def.id] = def
	return def


## Registers `def` under def.id in BuildLibrary's terrain-material catalog.
func add_terrain_material(def: TerrainMaterialDef) -> TerrainMaterialDef:
	# 1. Snapshot: first registration of an id records what was there so restore() can undo it.
	_remember(_previous_materials, BuildLibrary._materials_by_id, def.id)
	BuildLibrary._materials_by_id[def.id] = def
	return def


## Puts back every id this sandbox touched (or erases the synthetic one); never clears the rest.
func restore() -> void:
	# 1. Buildables: undo the touched ids only.
	_restore(_previous_buildables, BuildLibrary._defs_by_id)
	# 2. Materials: undo the touched ids only.
	_restore(_previous_materials, BuildLibrary._materials_by_id)


# ===================
# Auxiliary Functions
# ===================

func _remember(previous: Dictionary, live: Dictionary, id: String) -> void:
	## Auxiliary: first registration of an id records what was there (null when nothing).
	if not previous.has(id):
		previous[id] = live.get(id, null)


func _restore(previous: Dictionary, live: Dictionary) -> void:
	## Auxiliary: reinstates or erases each remembered id in `live`, then forgets them.
	for id: String in previous:
		if previous[id] != null:
			live[id] = previous[id]
		else:
			live.erase(id)
	previous.clear()
