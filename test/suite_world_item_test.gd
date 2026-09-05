extends GdUnitTestSuite

## Unit tests for WorldItem (dropped items, physics spawning, reservation, and hauling interactions).

const Doubles = preload("res://test/helpers/doubles.gd")
const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const WorldItemScript = preload("res://subsystems/inventory/world_item.gd")
const PickupActionScript = preload("res://subsystems/actions/pickup_action.gd")
const ToggleForbiddenActionScript = preload("res://subsystems/actions/toggle_forbidden_action.gd")

var _wood: ItemDef
var _stone: ItemDef
var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)

	_wood = ItemDef.new()
	_wood.id = "wood"
	_wood.weight = 1.0
	auto_free(_wood)

	_stone = ItemDef.new()
	_stone.id = "stone"
	_stone.weight = 2.0
	auto_free(_stone)

	if ItemDB != null:
		ItemDB._defs_by_id["wood"] = _wood
		ItemDB._defs_by_id["stone"] = _stone


func after_test() -> void:
	if ItemDB != null:
		ItemDB._defs_by_id.erase("wood")
		ItemDB._defs_by_id.erase("stone")
	_sandbox.restore()


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


func test_world_item_reservation_lifecycle() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 4, false)
	_sandbox.container.add_child(item)

	assert_bool(item.is_reserved()).is_false()
	assert_object(item.get_claimer()).is_null()

	var counter := Doubles.SignalCounter.new(item.reservation_changed)

	# 1. Reserve by worker A
	var worker_a := "colonist_1"
	var ok_a := item.reserve(worker_a)
	assert_bool(ok_a).is_true()
	assert_bool(item.is_reserved()).is_true()
	assert_bool(item.is_reserved_by(worker_a)).is_true()
	assert_int(counter.count).is_equal(1)

	# 2. Worker B attempts to reserve while A holds claim -> denied
	var worker_b := "colonist_2"
	var ok_b := item.reserve(worker_b)
	assert_bool(ok_b).is_false()
	assert_bool(item.is_reserved_by(worker_a)).is_true()

	# 3. Worker B attempts to unreserve A's claim -> ignored
	item.unreserve(worker_b)
	assert_bool(item.is_reserved()).is_true()

	# 4. Worker A releases claim -> unreserved
	item.unreserve(worker_a)
	assert_bool(item.is_reserved()).is_false()
	assert_int(counter.count).is_equal(2)

	# 5. Setting forbidden unreserves held claim
	item.reserve(worker_a)
	assert_bool(item.is_reserved()).is_true()
	item.set_forbidden(true)
	assert_bool(item.is_reserved()).is_false()
	assert_int(counter.read()).is_equal(4)


func test_world_item_urgent_haul_flag() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("stone", 2, false)

	var counter := Doubles.SignalCounter.new(item.urgent_haul_changed)
	assert_bool(item.is_urgent_haul()).is_false()

	item.set_urgent_haul(true)
	assert_bool(item.is_urgent_haul()).is_true()
	assert_int(counter.read()).is_equal(1)


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


func test_player_drop_item_spawns_world_item() -> void:
	var player_scene: PackedScene = load("res://subsystems/player/player.tscn")
	var player: Player = auto_free(player_scene.instantiate())
	get_tree().root.add_child(player)

	player.add_item("dirt", 2)
	assert_bool(player.has_item("dirt", 2)).is_true()

	var dropped: WorldItem = player.drop_item("dirt", 1)
	if dropped != null:
		auto_free(dropped)
		assert_str(dropped.item_id).is_equal("dirt")
		assert_int(dropped.count).is_equal(1)
	assert_bool(player.has_item("dirt", 1)).is_true()
	assert_bool(player.has_item("dirt", 2)).is_false()

	var dropped_all: WorldItem = player.drop_item("dirt", 1)
	if dropped_all != null:
		auto_free(dropped_all)
		assert_str(dropped_all.item_id).is_equal("dirt")
		assert_int(dropped_all.count).is_equal(1)
	assert_bool(player.has_item("dirt", 1)).is_false()

	get_tree().root.remove_child(player)


func test_world_item_registered_with_colony_and_removed_on_forbid() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 5, false)
	_sandbox.container.add_child(item)

	# Verify job board has a haul job targeting this item
	var jobs := _sandbox.test_board.get_jobs()
	var haul_jobs := jobs.filter(func(j: Job) -> bool: return j.target_node == item)
	assert_int(haul_jobs.size()).is_equal(1)
	var haul_job: Job = haul_jobs[0]
	assert_str(haul_job.labor_id).is_equal("hauling")

	# Forbidding item removes the haul job
	item.set_forbidden(true)
	jobs = _sandbox.test_board.get_jobs()
	haul_jobs = jobs.filter(func(j: Job) -> bool: return j.target_node == item)
	assert_int(haul_jobs.size()).is_equal(0)

	# Unforbidding restores the haul job
	item.set_forbidden(false)
	jobs = _sandbox.test_board.get_jobs()
	haul_jobs = jobs.filter(func(j: Job) -> bool: return j.target_node == item)
	assert_int(haul_jobs.size()).is_equal(1)


func test_world_item_proximity_job_selection() -> void:
	_sandbox.make_crate("wood", 0)
	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3(0.0, 0.0, 0.0)
	colonist.labor_priorities["hauling"] = 3

	# Spawn distant item (at x=20) and near item (at x=3)
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var far_item: WorldItem = auto_free(scene.instantiate())
	far_item.position = Vector3(20.0, 0.0, 0.0)
	far_item.setup("wood", 5, false)
	_sandbox.container.add_child(far_item)

	var near_item: WorldItem = auto_free(scene.instantiate())
	near_item.position = Vector3(3.0, 0.0, 0.0)
	near_item.setup("wood", 5, false)
	_sandbox.container.add_child(near_item)

	var best_job = _sandbox.test_board.get_best_job_for(colonist)
	assert_object(best_job).is_not_null()
	assert_object(best_job.target_node).is_same(near_item)


func test_world_item_hauling_execution_and_storage() -> void:
	var crate := _sandbox.make_crate("wood", 0)
	crate.global_position = Vector3(10.0, 0.0, 0.0)

	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3(0.0, 0.0, 0.0)
	colonist.labor_priorities["hauling"] = 3

	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.position = Vector3(2.0, 0.0, 0.0)
	item.setup("wood", 4, false)
	_sandbox.container.add_child(item)

	var haul_job = _sandbox.test_board.get_best_job_for(colonist)
	assert_object(haul_job).is_not_null()

	# 1. First cycle: walk target is WorldItem position
	var site_1 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_1).is_equal(item.global_position)

	# Complete pickup
	haul_job.def.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count("wood")).is_equal(4)

	# 2. Second cycle: walk target is crate position
	var site_2 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_2).is_equal(crate.global_position)

	# Complete deliver
	haul_job.def.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count("wood")).is_equal(0)
	var crate_inv := _sandbox.test_registry.inventory_of(crate)
	assert_int(crate_inv.get_item_count("wood")).is_equal(4)


func test_storage_registry_find_storage_for() -> void:
	var crate_small := _sandbox.make_crate("wood", 0)
	crate_small.global_position = Vector3(2.0, 0.0, 0.0)
	var inv_small := _sandbox.test_registry.inventory_of(crate_small)
	inv_small.capacity = 2.0  # holds up to 2 wood (weight 1.0)

	var crate_large := _sandbox.make_crate("wood", 0)
	crate_large.global_position = Vector3(10.0, 0.0, 0.0)
	var inv_large := _sandbox.test_registry.inventory_of(crate_large)
	inv_large.capacity = 50.0

	# 1 wood fits in nearest small crate
	var found_1 := _sandbox.test_registry.find_storage_for("wood", Vector3.ZERO, 1)
	assert_object(found_1).is_same(crate_small)

	# 5 wood does not fit in small crate (needs large crate at x=10)
	var found_5 := _sandbox.test_registry.find_storage_for("wood", Vector3.ZERO, 5)
	assert_object(found_5).is_same(crate_large)


func test_storage_registry_colony_stock_excludes_reserved() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 5, false)
	_sandbox.container.add_child(item)

	# Unreserved stock
	var unreserved_stock := _sandbox.test_registry.colony_stock("wood")
	assert_int(unreserved_stock).is_equal(5)

	# Reserve item
	item.reserve("hauler_1")
	var stock_after_reserve := _sandbox.test_registry.colony_stock("wood", null, 50.0, false)
	assert_int(stock_after_reserve).is_equal(0)

	# Include reserved explicitly
	var stock_with_reserved := _sandbox.test_registry.colony_stock("wood", null, 50.0, true)
	assert_int(stock_with_reserved).is_equal(5)

func test_hide_moving_thrown_item_disables_collisions_and_group() -> void:
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("wood", 5, false)
	_sandbox.container.add_child(item)

	# Simulate active thrown item with linear/angular velocity
	item.linear_velocity = Vector3(5.0, 2.0, 5.0)
	item.angular_velocity = Vector3(1.0, 1.0, 1.0)
	item.reserve("hauler_1")

	# Hide item on pickup
	item.hide_item()

	assert_bool(item.visible).is_false()
	assert_vector(item.linear_velocity).is_equal(Vector3.ZERO)
	assert_vector(item.angular_velocity).is_equal(Vector3.ZERO)
	assert_int(item.collision_layer).is_equal(0)
	assert_int(item.collision_mask).is_equal(0)
	assert_bool(item.is_in_group("world_items")).is_false()

	var col: CollisionShape3D = item.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		assert_bool(col.disabled).is_true()

func test_multi_item_haul_gathering_same_type() -> void:
	var crate := _sandbox.make_crate("wood", 0)
	crate.global_position = Vector3(20.0, 0.0, 0.0)

	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3(0.0, 0.0, 0.0)
	colonist.labor_priorities["hauling"] = 3
	colonist.inventory.capacity = 50.0

	# Spawn Item 1 at x=2 and Item 2 at x=4
	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item1: WorldItem = auto_free(scene.instantiate())
	item1.position = Vector3(2.0, 0.0, 0.0)
	item1.setup("wood", 2, false)
	_sandbox.container.add_child(item1)

	var item2: WorldItem = auto_free(scene.instantiate())
	item2.position = Vector3(4.0, 0.0, 0.0)
	item2.setup("wood", 3, false)
	_sandbox.container.add_child(item2)

	var haul_job = _sandbox.test_board.get_best_job_for(colonist)
	assert_object(haul_job).is_not_null()

	# Cycle 1: walk target is Item 1 position
	var site_1 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_1).is_equal(item1.global_position)
	haul_job.def.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count("wood")).is_equal(2)

	# Cycle 2: colonist still has capacity, so work_site targets nearby Item 2
	var site_2 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_2).is_equal(item2.global_position)
	colonist.global_position = item2.global_position
	haul_job.def.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count("wood")).is_equal(5)

	# Cycle 3: no more ground items, work_site targets crate
	var site_3 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_3).is_equal(crate.global_position)
	colonist.global_position = crate.global_position
	haul_job.def.complete(colonist, haul_job)

	assert_int(colonist.inventory.get_item_count("wood")).is_equal(0)
	var crate_inv := _sandbox.test_registry.inventory_of(crate)
	assert_int(crate_inv.get_item_count("wood")).is_equal(5)


func test_multi_item_haul_stops_when_capacity_full() -> void:
	var crate := _sandbox.make_crate("wood", 0)
	crate.global_position = Vector3(20.0, 0.0, 0.0)

	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3(0.0, 0.0, 0.0)
	colonist.labor_priorities["hauling"] = 3
	colonist.inventory.capacity = 2.0  # only holds 2 wood

	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item1: WorldItem = auto_free(scene.instantiate())
	item1.position = Vector3(2.0, 0.0, 0.0)
	item1.setup("wood", 2, false)
	_sandbox.container.add_child(item1)

	var item2: WorldItem = auto_free(scene.instantiate())
	item2.position = Vector3(4.0, 0.0, 0.0)
	item2.setup("wood", 3, false)
	_sandbox.container.add_child(item2)

	var haul_job = _sandbox.test_board.get_best_job_for(colonist)
	assert_object(haul_job).is_not_null()

	# Cycle 1: pickup Item 1 fills capacity
	haul_job.def.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count("wood")).is_equal(2)

	# Cycle 2: capacity full -> immediately targets crate, ignoring Item 2
	var site_2 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_2).is_equal(crate.global_position)


func test_multi_item_haul_ignores_unreachable_wall() -> void:
	var crate := _sandbox.make_crate("wood", 0)
	crate.global_position = Vector3(-10.0, 0.0, 0.0)

	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3(0.0, 0.0, 0.0)
	colonist.labor_priorities["hauling"] = 3
	colonist.inventory.capacity = 50.0

	# Setup solid floor for y=0 except wall at x=3
	var solid := {}
	for x in range(-15, 15):
		for z in range(-5, 5):
			solid[Vector3i(x, 0, z)] = true
	# Add a tall wall at x=3
	for y in range(1, 5):
		for z in range(-5, 5):
			solid[Vector3i(3, y, z)] = true

	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	var predicate := func(cell: Vector3i) -> bool:
		return not solid.has(cell) and solid.has(cell + Vector3i(0, -1, 0)) and not solid.has(cell + Vector3i(0, 1, 0))
	finder.set_walkability(predicate)
	colonist.pathfinder = finder

	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item1: WorldItem = auto_free(scene.instantiate())
	item1.position = Vector3(1.0, 1.0, 0.0)
	item1.setup("wood", 2, false)
	_sandbox.container.add_child(item1)

	var item2: WorldItem = auto_free(scene.instantiate())
	item2.position = Vector3(5.0, 1.0, 0.0)  # Behind wall at x=3
	item2.setup("wood", 2, false)
	_sandbox.container.add_child(item2)

	var haul_job = _sandbox.test_board.get_best_job_for(colonist)
	assert_object(haul_job).is_not_null()

	# Cycle 1: pickup item1 on colonist side of wall
	haul_job.def.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count("wood")).is_equal(2)

	# Cycle 2: item2 is behind wall and unreachable -> work_site routes to crate
	var site_2 = haul_job.def.work_site(colonist, haul_job)
	assert_vector(site_2).is_equal(crate.global_position)


func test_world_item_job_single_assignee_and_surplus_delivery() -> void:
	var colonist1: Colonist = _sandbox.make_colonist()
	var colonist2: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("wood", 0)
	crate.global_position = Vector3(10.0, 0.0, 0.0)

	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.position = Vector3(2.0, 0.0, 0.0)
	item.setup("wood", 5, false)
	_sandbox.container.add_child(item)

	var job = _sandbox.test_board.get_best_job_for(colonist1)
	assert_object(job).is_not_null()
	assert_int(job.max_assignees).is_equal(1)

	# Assign colonist1
	assert_bool(job.try_assign(colonist1)).is_true()

	# Colonist2 should NOT be able to claim or assign to the same ground item job
	var job_c2 = _sandbox.test_board.get_best_job_for(colonist2)
	assert_object(job_c2).is_null()

	# Give colonist1 some existing dirt in inventory from a previous action
	colonist1.inventory.add("dirt", 4)

	# Cycle 1: pickup
	job.def.complete(colonist1, job)
	assert_int(colonist1.inventory.get_item_count("wood")).is_equal(5)
	assert_int(colonist1.inventory.get_item_count("dirt")).is_equal(4)

	# Cycle 2: deliver to crate -> should deposit wood AND surplus dirt
	job.def.complete(colonist1, job)
	assert_int(colonist1.inventory.get_item_count("wood")).is_equal(0)
	assert_int(colonist1.inventory.get_item_count("dirt")).is_equal(0)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("wood")).is_equal(5)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("dirt")).is_equal(4)


func test_store_carried_items_prefers_crate_with_capacity_and_drops_on_floor_when_full() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3.ZERO
	# Give colonist some dirt to store
	colonist.inventory.add("dirt", 6)

	# Full crate 1 at distance 2.0
	var full_crate: Furniture = _sandbox.make_crate("wood", 0)
	full_crate.global_position = Vector3(2.0, 0.0, 0.0)
	var full_inv := _sandbox.test_registry.inventory_of(full_crate)
	full_inv.capacity = 1.0 # Very low capacity
	full_inv.add("wood", 1) # Full!

	# Empty shelf/crate 2 at distance 10.0
	var empty_crate: Furniture = _sandbox.make_crate("dirt", 0)
	empty_crate.global_position = Vector3(10.0, 0.0, 0.0)
	var empty_inv := _sandbox.test_registry.inventory_of(empty_crate)
	empty_inv.capacity = 50.0

	# get_best_job_for should route to empty_crate (with capacity) rather than full_crate
	var job = _sandbox.test_board.get_best_job_for(colonist)
	assert_object(job).is_not_null()
	assert_str(job.title).is_equal("Store Carried Items")
	var site = job.def.work_site(colonist, job)
	assert_vector(site).is_equal(empty_crate.global_position)

	# Complete deposit
	job.def.complete(colonist, job)
	assert_int(colonist.inventory.get_item_count("dirt")).is_equal(0)
	assert_int(empty_inv.get_item_count("dirt")).is_equal(6)


func test_world_item_custom_mesh_and_autofit_collision() -> void:
	var custom_def := ItemDef.new()
	custom_def.id = "custom_test_item"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.2
	cylinder.bottom_radius = 0.2
	cylinder.height = 1.0
	custom_def.mesh = cylinder
	custom_def.visual_scale = Vector3(1.0, 2.0, 1.0)
	var custom_mat := StandardMaterial3D.new()
	custom_mat.albedo_color = Color.BLUE
	custom_def.material = custom_mat

	ItemDB._defs_by_id["custom_test_item"] = custom_def

	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("custom_test_item", 1, false)
	_sandbox.container.add_child(item)

	assert_object(item.mesh_instance.mesh).is_equal(cylinder)
	assert_vector(item.mesh_instance.scale).is_equal(Vector3(1.0, 2.0, 1.0))
	assert_object(item.mesh_instance.material_override).is_equal(custom_mat)

	var col_shape := item.collision_shape.shape as BoxShape3D
	assert_object(col_shape).is_not_null()
	assert_float(col_shape.size.x).is_equal_approx(0.4, 0.01)
	assert_float(col_shape.size.y).is_equal_approx(2.0, 0.01)
	assert_float(col_shape.size.z).is_equal_approx(0.4, 0.01)

	ItemDB._defs_by_id.erase("custom_test_item")


func test_world_item_custom_scene_and_autofit_collision() -> void:
	var custom_def := ItemDef.new()
	custom_def.id = "custom_scene_item"

	var packed_scene := PackedScene.new()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.2
	cylinder.bottom_radius = 0.2
	cylinder.height = 1.0
	mi.mesh = cylinder
	root.add_child(mi)
	mi.owner = root
	packed_scene.pack(root)
	root.free()

	custom_def.scene = packed_scene
	custom_def.visual_scale = Vector3(1.0, 2.0, 1.0)

	ItemDB._defs_by_id["custom_scene_item"] = custom_def

	var scene: PackedScene = load("res://subsystems/inventory/world_item.tscn")
	var item: WorldItem = auto_free(scene.instantiate())
	item.setup("custom_scene_item", 1, false)
	_sandbox.container.add_child(item)

	assert_bool(item.mesh_instance.visible).is_false()
	assert_object(item._scene_instance).is_not_null()
	assert_vector(item._scene_instance.scale).is_equal(Vector3(1.0, 2.0, 1.0))

	var col_shape := item.collision_shape.shape as BoxShape3D
	assert_object(col_shape).is_not_null()
	assert_float(col_shape.size.x).is_equal_approx(0.4, 0.01)
	assert_float(col_shape.size.y).is_equal_approx(2.0, 0.01)
	assert_float(col_shape.size.z).is_equal_approx(0.4, 0.01)

	ItemDB._defs_by_id.erase("custom_scene_item")


func test_spawn_at_aligns_above_ground_surface() -> void:
	var static_body: StaticBody3D = auto_free(StaticBody3D.new())
	static_body.collision_layer = 1  # Layer 1 (World)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 1.0, 10.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, 0.0, 0.0)
	static_body.add_child(floor_shape)
	_sandbox.container.add_child(static_body)

	var item: WorldItem = WorldItemScript.spawn_at(_sandbox.container, "dirt", 1, Vector3(0.0, 0.4, 0.0), Vector3.UP, 0.0)
	assert_object(item).is_not_null()
	auto_free(item)

	assert_bool(item.global_position.y > 0.5).is_true()
