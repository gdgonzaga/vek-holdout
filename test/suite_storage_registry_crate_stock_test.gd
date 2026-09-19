extends GdUnitTestSuite
## Tests for StorageRegistry.crate_stock: the crates-only stock count the Gear picker uses,
## since FetchEquipmentJob can only take from crates (colony_stock also counts pockets and
## ground items). Content-agnostic: the item is synthetic and ItemDB is swapped-and-restored.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const ITEM_ID: String = "crate_stock_test_item"

var _sandbox: ColonySandbox
var _previous_def: ItemDef = null


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = ITEM_ID
	def.weight = 1.0
	_previous_def = ItemDB._defs_by_id.get(ITEM_ID, null)
	ItemDB._defs_by_id[ITEM_ID] = def


func after_test() -> void:
	if _previous_def != null:
		ItemDB._defs_by_id[ITEM_ID] = _previous_def
	else:
		ItemDB._defs_by_id.erase(ITEM_ID)
	_sandbox.restore()


func test_crate_stock_is_zero_when_no_crate_holds_the_item() -> void:
	_sandbox.make_crate("some_other_item", 4)

	assert_int(_sandbox.test_registry.crate_stock(ITEM_ID)).is_equal(0)


func test_crate_stock_sums_across_crates() -> void:
	_sandbox.make_crate(ITEM_ID, 2)
	_sandbox.make_crate(ITEM_ID, 3)

	assert_int(_sandbox.test_registry.crate_stock(ITEM_ID)).is_equal(5)


func test_crate_stock_ignores_ground_items_that_colony_stock_counts() -> void:
	_sandbox.make_crate(ITEM_ID, 2)
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var ground: WorldItem = auto_free(scene.instantiate())
	ground.setup(ITEM_ID, 5, false)
	_sandbox.container.add_child(ground)

	assert_int(_sandbox.test_registry.crate_stock(ITEM_ID)).is_equal(2)
	assert_int(_sandbox.test_registry.colony_stock(ITEM_ID)).is_equal(7)
