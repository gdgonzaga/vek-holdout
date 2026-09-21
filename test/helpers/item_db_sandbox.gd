extends RefCounted
## In-memory ItemDefs registered in ItemDB for one test and restored afterwards. Only the
## ids a test touches are restored, so registering "sword" cannot disturb anything else in
## the autoload. Use instead of reading shipped item content.
##
## Usage:
##   const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")
##   var _items: ItemDbSandbox
##   _items = ItemDbSandbox.new(self)        # in before_test
##   _items.add_item("wood")
##   _items.restore()                        # in after_test

var _suite: GdUnitTestSuite
var _previous: Dictionary = {}  # item_id -> ItemDef, or null when the id was not registered


func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite


# =================
# Primary Functions
# =================

## Registers a bare in-memory ItemDef (id, optional display name, optional tags). Callers that
## need more (weight, equippable) set it on the returned def.
func add_item(item_id: String, display_name: String = "", tags: Array[String] = []) -> ItemDef:
	var def: ItemDef = _suite.auto_free(ItemDef.new())
	def.id = item_id
	def.resource_name = display_name
	def.tags = tags
	# 1. Registration: putting the def in ItemDB while remembering what it displaces.
	return register(def)


## Registers `def` under def.id, remembering the original entry once per id.
func register(def: ItemDef) -> ItemDef:
	# 1. Snapshot: first registration of an id records what was there so restore() can undo it.
	_remember(def.id)
	ItemDB._defs_by_id[def.id] = def
	return def


## Puts back every id this sandbox touched (or erases the synthetic one); never clears the rest.
func restore() -> void:
	for item_id: String in _previous:
		# 1. Undo: reinstate the original def, or erase an id that did not exist before.
		_restore_one(item_id)
	_previous.clear()


# ===================
# Auxiliary Functions
# ===================

func _remember(item_id: String) -> void:
	## Auxiliary: first registration of an id records what was there (null when nothing).
	if not _previous.has(item_id):
		_previous[item_id] = ItemDB._defs_by_id.get(item_id, null)


func _restore_one(item_id: String) -> void:
	## Auxiliary: reinstates or erases a single id.
	if _previous[item_id] != null:
		ItemDB._defs_by_id[item_id] = _previous[item_id]
	else:
		ItemDB._defs_by_id.erase(item_id)
