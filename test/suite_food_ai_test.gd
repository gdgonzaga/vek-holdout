extends GdUnitTestSuite

## Unit tests for LimboAI food tasks, pocket priority, empty-crate race resilience,
## unreachable food blacklisting, and player consumption.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

const BTActionFindFoodScript = preload("res://subsystems/ai/tasks/actions/bt_action_find_food.gd")
const BTActionFetchFoodScript = preload("res://subsystems/ai/tasks/actions/bt_action_fetch_food.gd")
const BTActionEatFoodScript = preload("res://subsystems/ai/tasks/actions/bt_action_eat_food.gd")

const FoodParamsScript = preload("res://data/capability_params/food_params.gd")
const ItemDefScript = preload("res://data/items/item_def.gd")
const HungerComponentScript = preload("res://subsystems/colonists/hunger_component.gd")

var _sandbox: ColonySandbox
var _blackboard: Blackboard
var _actor: Colonist
var _previous_defs: Dictionary = {}
var _test_food_id: String = "test_ration"


# =================
# Suite Lifecycle
# =================

func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_blackboard = Blackboard.new()
	_actor = _sandbox.make_colonist()

	# Setup in-memory test food ItemDef
	var food_params: FoodParams = auto_free(FoodParamsScript.new()) as FoodParams
	food_params.nutrition_value = 0.45
	food_params.health_restore = 6
	food_params.eat_duration = 0.2

	var food_def: ItemDef = auto_free(ItemDefScript.new()) as ItemDef
	food_def.id = _test_food_id
	food_def.weight = 0.2
	food_def.tags = ["food"]
	food_def.food = food_params

	_previous_defs[_test_food_id] = ItemDB._defs_by_id.get(_test_food_id, null)
	ItemDB._defs_by_id[_test_food_id] = food_def


func after_test() -> void:
	_sandbox.restore()
	if _previous_defs.has(_test_food_id) and _previous_defs[_test_food_id] != null:
		ItemDB._defs_by_id[_test_food_id] = _previous_defs[_test_food_id]
	else:
		ItemDB._defs_by_id.erase(_test_food_id)
	_previous_defs.clear()


# =================
# Primary Tests
# =================

func test_find_food_prioritizes_inventory_pockets() -> void:
	_actor.inventory.add(_test_food_id, 2)
	_blackboard.set_var(&"current_goal", &"eat")

	var task: BTAction = auto_free(BTActionFindFoodScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)

	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)
	assert_str(str(_blackboard.get_var(&"food_source_type"))).is_equal("inventory")
	assert_str(str(_blackboard.get_var(&"food_item_id"))).is_equal(_test_food_id)


func test_find_food_locates_crate_source_when_pockets_empty() -> void:
	var crate: Furniture = _sandbox.make_crate(_test_food_id, 5)
	_blackboard.set_var(&"current_goal", &"eat")

	var task: BTAction = auto_free(BTActionFindFoodScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)

	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)
	assert_str(str(_blackboard.get_var(&"food_source_type"))).is_equal("crate")
	assert_object(_blackboard.get_var(&"food_source_node")).is_equal(crate)


func test_find_food_ignores_blacklisted_crate() -> void:
	var crate: Furniture = _sandbox.make_crate(_test_food_id, 5)
	_actor.brain.blacklist_food_source(crate, 10.0)

	_blackboard.set_var(&"current_goal", &"eat")

	var task: BTAction = auto_free(BTActionFindFoodScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)

	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


func test_fetch_food_succeeds_immediately_for_inventory() -> void:
	_blackboard.set_var(&"food_source_type", &"inventory")

	var task: BTAction = auto_free(BTActionFetchFoodScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)

	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)


func test_fetch_food_transfers_from_crate() -> void:
	var crate: Furniture = _sandbox.make_crate(_test_food_id, 3)
	_blackboard.set_var(&"food_source_type", &"crate")
	_blackboard.set_var(&"food_source_node", crate)
	_blackboard.set_var(&"food_item_id", _test_food_id)

	var task: BTAction = auto_free(BTActionFetchFoodScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)

	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)
	assert_int(_actor.inventory.get_item_count(_test_food_id)).is_equal(1)

	var crate_inv: StorageInventory = crate.get_node("StorageInventory") as StorageInventory
	assert_int(crate_inv.get_item_count(_test_food_id)).is_equal(2)


func test_fetch_food_fails_cleanly_if_crate_emptied() -> void:
	var crate: Furniture = _sandbox.make_crate(_test_food_id, 0)
	_blackboard.set_var(&"food_source_type", &"crate")
	_blackboard.set_var(&"food_source_node", crate)
	_blackboard.set_var(&"food_item_id", _test_food_id)

	var task: BTAction = auto_free(BTActionFetchFoodScript.new()) as BTAction
	task.initialize(_actor, _blackboard, _actor)

	# Fails gracefully without throwing errors
	var status: int = task.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)
	assert_int(_actor.inventory.get_item_count(_test_food_id)).is_equal(0)


func test_eat_food_consumes_and_replenishes_hunger() -> void:
	_actor.inventory.add(_test_food_id, 1)
	_actor.hunger_component.current_hunger = 0.2

	_blackboard.set_var(&"food_item_id", _test_food_id)
	_blackboard.set_var(&"current_goal", &"eat")

	var task: BTAction = auto_free(BTActionEatFoodScript.new()) as BTAction
	task.default_eat_duration = 0.2
	task.initialize(_actor, _blackboard, _actor)

	# During eating: RUNNING
	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)
	assert_int(_actor.inventory.get_item_count(_test_food_id)).is_equal(1)

	# Finished eating: SUCCESS
	assert_int(task.execute(0.15)).is_equal(BTAction.SUCCESS)
	assert_int(_actor.inventory.get_item_count(_test_food_id)).is_equal(0)
	assert_float(_actor.hunger_component.current_hunger).is_equal_approx(0.65, 0.01)
	assert_str(str(_blackboard.get_var(&"current_goal"))).is_equal("none")


func test_eat_food_interruption_preserves_item() -> void:
	_actor.inventory.add(_test_food_id, 1)

	var task: BTAction = auto_free(BTActionEatFoodScript.new()) as BTAction
	task.default_eat_duration = 1.0
	task.initialize(_actor, _blackboard, _actor)

	# Tick partially then exit (simulate task interruption)
	assert_int(task.execute(0.05)).is_equal(BTAction.RUNNING)
	task.abort()

	# Item was not consumed
	assert_int(_actor.inventory.get_item_count(_test_food_id)).is_equal(1)


func test_player_consumes_food_restores_hunger_and_hp() -> void:
	var player: Player = _sandbox.make_player()
	player.inventory.add(_test_food_id, 1)
	player.current_hp = 50
	player.max_hp = 100
	player.hunger_component.current_hunger = 0.3

	var success: bool = player.consume_food_item(_test_food_id)
	assert_bool(success).is_true()
	assert_int(player.inventory.get_item_count(_test_food_id)).is_equal(0)
	assert_float(player.hunger_component.current_hunger).is_equal_approx(0.75, 0.01)
	assert_int(player.current_hp).is_equal(56)
