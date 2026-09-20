extends GdUnitTestSuite

## Player-facing item names: ItemDef.get_display_name() (authored resource_name, else
## id) and ItemDB.get_display_name(item_id) (same, and the raw id for an unknown item).
## Content-agnostic: in-memory ItemDefs, registered in ItemDB only for the test.

var _previous_defs: Dictionary = {}


func after_test() -> void:
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


func _make_item(item_id: String, display: String = "") -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.resource_name = display
	return def


func _register(def: ItemDef) -> void:
	if not _previous_defs.has(def.id):
		_previous_defs[def.id] = ItemDB._defs_by_id.get(def.id, null)
	ItemDB._defs_by_id[def.id] = def


func test_def_display_name_prefers_the_authored_name() -> void:
	assert_str(_make_item("test_name_id", "Fancy Name").get_display_name()).is_equal("Fancy Name")


func test_def_display_name_falls_back_to_the_id() -> void:
	assert_str(_make_item("test_name_id").get_display_name()).is_equal("test_name_id")


func test_db_display_name_resolves_a_registered_item() -> void:
	_register(_make_item("test_name_id", "Fancy Name"))
	assert_str(ItemDB.get_display_name("test_name_id")).is_equal("Fancy Name")


func test_db_display_name_falls_back_to_the_id_for_an_unknown_item() -> void:
	# Break caught: a UI listing an orphaned stack must show something readable, not "".
	assert_str(ItemDB.get_display_name("test_name_missing")).is_equal("test_name_missing")
