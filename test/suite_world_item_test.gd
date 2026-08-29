extends GdUnitTestSuite

## Unit tests for WorldItem (dropped items, physics spawning, and pickup interactions).

const Doubles = preload("res://test/helpers/doubles.gd")
const WorldItemScript = preload("res://subsystems/inventory/world_item.gd")
const PickupActionScript = preload("res://subsystems/actions/pickup_action.gd")
const ToggleForbiddenActionScript = preload("res://subsystems/actions/toggle_forbidden_action.gd")

var _wood: ItemDef
var _stone: ItemDef


func before_test() -> void:
	_wood = ItemDef.new()
	_wood.id = "wood"
	_wood.weight = 1.0
	auto_free(_wood)

	_stone = ItemDef.new()
	_stone.id = "stone"
	_stone.weight = 2.0
	auto_free(_stone)


func _make_inventory(capacity: float, defs: Dictionary) -> Inventory:
	var inv := Doubles.MockInventory.new()
	inv.capacity = capacity
	inv._defs = defs
	auto_free(inv)
	return inv


func test_world_item_setup_and_properties() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 5, false)

	assert_str(item.item_id).is_equal("wood")
	assert_int(item.count).is_equal(5)
	assert_bool(item.forbidden).is_false()
	assert_bool(item.is_forbidden()).is_false()


func test_set_forbidden_updates_state_and_interaction() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 3, false)

	var counter := Doubles.SignalCounter.new(item.forbidden_changed)
	item.set_forbidden(true)

	assert_int(counter.read()).is_equal(1)
	assert_bool(item.forbidden).is_true()
	assert_bool(item.is_forbidden()).is_true()


func test_pickup_action_transfers_items_to_inventory() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 4, false)

	var actor: Node = auto_free(Node.new())
	var inv := _make_inventory(20.0, {"wood": _wood})
	actor.add_child(inv)

	var action := PickupActionScript.new()
	action.execute(actor, item)

	assert_int(inv.get_item_count("wood")).is_equal(4)
	assert_int(item.count).is_equal(0)


func test_pickup_action_partial_capacity() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 10, false)

	var actor: Node = auto_free(Node.new())
	# Capacity 3.0 allows only 3 wood (weight 1.0 each)
	var inv := _make_inventory(3.0, {"wood": _wood})
	actor.add_child(inv)

	var action := PickupActionScript.new()
	action.execute(actor, item)

	assert_int(inv.get_item_count("wood")).is_equal(3)
	assert_int(item.count).is_equal(7)


func test_toggle_forbidden_action() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("stone", 2, false)

	var actor: Node = auto_free(Node.new())
	var action := ToggleForbiddenActionScript.new()

	action.execute(actor, item)
	assert_bool(item.forbidden).is_true()

	action.execute(actor, item)
	assert_bool(item.forbidden).is_false()


func test_spawn_at_adds_to_parent_node() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	var spawn_pos := Vector3(5.0, 2.0, 5.0)

	var item: WorldItem = WorldItemScript.spawn_at(parent, "stone", 8, spawn_pos, Vector3.UP, 0.0)
	assert_object(item).is_not_null()
	auto_free(item)

	assert_str(item.item_id).is_equal("stone")
	assert_int(item.count).is_equal(8)
	assert_object(item.get_parent()).is_same(parent)
	assert_vector(item.position).is_equal(spawn_pos)


func test_wake_up_and_wake_items_near() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	var item: WorldItem = WorldItemScript.spawn_at(parent, "stone", 1, Vector3(2.0, 1.0, 2.0), Vector3.UP, 0.0)
	auto_free(item)
	item.freeze = true
	item.sleeping = true

	item.wake_up()
	assert_bool(item.freeze).is_false()
	assert_bool(item.sleeping).is_false()

	item.freeze = true
	item.sleeping = true

	# Put parent in tree so get_nodes_in_group works
	get_tree().root.add_child(parent)
	item.add_to_group("world_items")

	WorldItemScript.wake_items_near(get_tree(), Vector3(2.0, 1.0, 2.0), 3.0)
	assert_bool(item.freeze).is_false()
	assert_bool(item.sleeping).is_false()

	get_tree().root.remove_child(parent)
