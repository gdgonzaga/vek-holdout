extends GdUnitTestSuite
## Tests for StorageRegistry.crate_stock: the crates-only stock count the Gear picker uses,
## since FetchEquipmentJob can only take from crates (colony_stock also counts pockets and
## ground items). Content-agnostic: the item is synthetic and ItemDB is swapped-and-restored.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")
const FoodParamsScript = preload("res://data/capability_params/food_params.gd")
const ITEM_ID: String = "crate_stock_test_item"

var _sandbox: ColonySandbox
var _previous_def: ItemDef = null

## Registers synthetic food ItemDefs (FoodParams attached) for the
## find_best_food_source / colony_food_count tests below.
var _food_items: ItemDbSandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = ITEM_ID
	def.weight = 1.0
	_previous_def = ItemDB._defs_by_id.get(ITEM_ID, null)
	ItemDB._defs_by_id[ITEM_ID] = def
	_food_items = ItemDbSandbox.new(self)


func after_test() -> void:
	if _previous_def != null:
		ItemDB._defs_by_id[ITEM_ID] = _previous_def
	else:
		ItemDB._defs_by_id.erase(ITEM_ID)
	_food_items.restore()
	_sandbox.restore()


## Registers item_id in ItemDB with a FoodParams capability, so
## StorageRegistry._is_edible_item(item_id) recognizes it as food.
func _make_food_item(item_id: String) -> ItemDef:
	var def: ItemDef = _food_items.add_item(item_id)
	def.weight = 0.2
	def.food = auto_free(FoodParamsScript.new()) as FoodParams
	return def


## A ground WorldItem holding item_id, parented under the sandbox container at
## the given local (== global, container sits at the origin) position.
func _make_ground_item(item_id: String, count: int, pos: Vector3) -> WorldItem:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup(item_id, count, false)
	item.position = pos
	_sandbox.container.add_child(item)
	return item


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


# ── find_best_food_source(): nearest edible source across crates AND ground ─────

func test_find_best_food_source_prefers_nearer_ground_item_over_farther_crate() -> void:
	var item_id := "test_food_ground_wins"
	_make_food_item(item_id)

	var crate: Furniture = _sandbox.make_crate(item_id, 3)
	crate.global_position = Vector3(20.0, 0.0, 0.0)
	var ground: WorldItem = _make_ground_item(item_id, 2, Vector3(3.0, 0.0, 0.0))

	var result: Dictionary = _sandbox.test_registry.find_best_food_source(Vector3.ZERO)

	assert_str(str(result.get("source_type", ""))).is_equal("ground")
	assert_object(result.get("source_node")).is_same(ground)


func test_find_best_food_source_prefers_nearer_crate_over_farther_ground_item() -> void:
	var item_id := "test_food_crate_wins"
	_make_food_item(item_id)

	var crate: Furniture = _sandbox.make_crate(item_id, 3)
	crate.global_position = Vector3(3.0, 0.0, 0.0)
	_make_ground_item(item_id, 2, Vector3(20.0, 0.0, 0.0))

	var result: Dictionary = _sandbox.test_registry.find_best_food_source(Vector3.ZERO)

	assert_str(str(result.get("source_type", ""))).is_equal("crate")
	assert_object(result.get("source_node")).is_same(crate)


# ── colony_food_count(): total edible units across crates, ground and pockets ──

func test_colony_food_count_sums_food_across_crates_ground_and_pockets_ignoring_non_food() -> void:
	var food_id := "test_food_count_food"
	_make_food_item(food_id)
	# ITEM_ID (registered in before_test) carries no FoodParams and no "food" tag.
	_sandbox.make_crate(ITEM_ID, 9)

	_sandbox.make_crate(food_id, 3)
	_make_ground_item(food_id, 2, Vector3(5.0, 0.0, 0.0))

	var colonist: Colonist = _sandbox.make_colonist()
	colonist.inventory.add(food_id, 1)

	var player: Player = _sandbox.make_player()
	player.inventory.add(food_id, 4)

	assert_int(_sandbox.test_registry.colony_food_count()).is_equal(10)
