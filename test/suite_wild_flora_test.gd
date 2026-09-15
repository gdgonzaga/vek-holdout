extends GdUnitTestSuite
class_name SuiteWildFloraTest
## Unit tests for the Wild Flora subsystem (ARCH "Wild Flora"):
## - WildFloraDef and WildFloraStage data resolution
## - FurnitureLayer instantiation of WildFlora
## - Collision movement policy (blocking vs non-blocking shrubs)
## - HealthComponent integration, damage resolution, and felling
## - Perennial fruit foraging and regrowth stage reversion
## - Bounding box queries on FurnitureLayer

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox
var _furniture_layer: FurnitureLayer


func before_test() -> void:
	GameLog.clear()
	_sandbox = ColonySandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)


func after_test() -> void:
	_sandbox.restore()


func _create_test_flora_def(p_id: String, p_blocks_movement: bool = true) -> WildFloraDef:
	var def := WildFloraDef.new()
	def.id = p_id
	def.display_name = "Test Flora"
	def.hp = 100
	def.blocks_movement = p_blocks_movement
	def.growth_time_hours = 10.0
	def.destroy_on_fruit_harvest = false
	def.regrowth_stage_index = 1
	
	var stage0 := WildFloraStage.new()
	stage0.min_progress = 0.0
	stage0.max_hp = 30
	stage0.can_harvest_fruit = false
	
	var stage1 := WildFloraStage.new()
	stage1.min_progress = 0.5
	stage1.max_hp = 60
	stage1.can_harvest_fruit = false
	
	var stage2 := WildFloraStage.new()
	stage2.min_progress = 1.0
	stage2.max_hp = 100
	stage2.can_harvest_fruit = true
	
	def.stages = [stage0, stage1, stage2]
	return def


func test_wild_flora_stage_resolution() -> void:
	var def := _create_test_flora_def("test_stage_res")
	
	var st0 := def.get_stage_for_progress(0.0)
	assert_object(st0).is_not_null()
	assert_int(st0.max_hp).is_equal(30)
	assert_int(def.get_stage_index_for_progress(0.0)).is_equal(0)
	
	var st1 := def.get_stage_for_progress(0.7)
	assert_object(st1).is_not_null()
	assert_int(st1.max_hp).is_equal(60)
	assert_int(def.get_stage_index_for_progress(0.7)).is_equal(1)
	
	var st2 := def.get_stage_for_progress(1.0)
	assert_object(st2).is_not_null()
	assert_int(st2.max_hp).is_equal(100)
	assert_bool(st2.can_harvest_fruit).is_true()
	assert_int(def.get_stage_index_for_progress(1.0)).is_equal(2)


func test_wild_flora_fallback_stage_synthesis() -> void:
	var def := WildFloraDef.new()
	def.id = "test_empty_stages"
	def.hp = 150
	def.stages = []
	
	var eff := def.get_effective_stages()
	assert_int(eff.size()).is_equal(1)
	assert_int(eff[0].max_hp).is_equal(150)


func test_wild_flora_spawn_and_health_component() -> void:
	var def := _create_test_flora_def("test_spawn_flora")
	var anchor := Vector3i(2, 0, 2)
	
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	assert_object(node).is_not_null()
	assert_bool(node is WildFlora).is_true()
	
	var flora := node as WildFlora
	assert_object(flora.health_component).is_not_null()
	assert_bool(flora.health_component.show_damage_particles).is_false()


func test_wild_flora_take_damage_and_felling() -> void:
	var def := _create_test_flora_def("test_damage_flora")
	var anchor := Vector3i(4, 0, 4)
	
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	flora.set_growth_progress(1.0) # Full mature stage -> 100 HP
	
	assert_int(flora.health_component.current_hp).is_equal(100)
	
	# Deal non-lethal damage
	flora.take_damage(40)
	assert_int(flora.health_component.current_hp).is_equal(60)
	assert_bool(_furniture_layer.has_at(anchor)).is_true()
	
	# Deal lethal damage to fell
	flora.take_damage(60)
	assert_bool(_furniture_layer.has_at(anchor)).is_false()


func test_wild_flora_foraging_and_regrowth() -> void:
	var def := _create_test_flora_def("test_forage_flora")
	var anchor := Vector3i(6, 0, 6)
	
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	
	# Unripe -> cannot forage
	flora.set_growth_progress(0.5)
	assert_bool(flora.can_forage()).is_false()
	assert_bool(flora.forage(null)).is_false()
	
	# Mature -> can forage
	flora.set_growth_progress(1.0)
	# Note: stage2 harvest_yields is empty in helper, add dummy item def if needed or test forage logic
	def.stages[2].harvest_yields = []
	assert_bool(flora.can_forage()).is_false() # Empty yields -> false
	
	# Add an item amount to stage2
	var item_amount := ItemAmount.new()
	var dummy_item := ItemDef.new()
	dummy_item.id = "test_berry"
	item_amount.item_def = dummy_item
	item_amount.count = 3
	def.stages[2].harvest_yields = [item_amount]
	
	assert_bool(flora.can_forage()).is_true()
	
	# Forage fruit -> resets to stage 1 (min_progress = 0.5)
	var success := flora.forage(null)
	assert_bool(success).is_true()
	assert_float(flora.growth_progress).is_equal_approx(0.5, 0.01)
	assert_bool(_furniture_layer.has_at(anchor)).is_true()


func test_furniture_layer_box_queries() -> void:
	var def1 := _create_test_flora_def("flora_a")
	def1.tags = ["live_flora", "tree"]
	var def2 := _create_test_flora_def("flora_b")
	def2.tags = ["live_flora", "bush"]
	
	_furniture_layer.spawn(def1, Vector3i(1, 0, 1), 0)
	_furniture_layer.spawn(def2, Vector3i(4, 0, 4), 0)
	_furniture_layer.spawn(def1, Vector3i(20, 0, 20), 0)
	
	var in_box := _furniture_layer.get_furniture_in_box(Vector3i(0, 0, 0), Vector3i(10, 0, 10))
	assert_int(in_box.size()).is_equal(2)
	
	var trees_in_box := _furniture_layer.get_wild_flora_in_box(Vector3i(0, 0, 0), Vector3i(10, 0, 10), "tree")
	assert_int(trees_in_box.size()).is_equal(1)
	assert_str(trees_in_box[0].def_id).is_equal("flora_a")


func test_wild_flora_foraging_spawns_drops_towards_actor() -> void:
	var def := _create_test_flora_def("test_forage_offset_flora")
	var item_amount := ItemAmount.new()
	var dummy_item := ItemDef.new()
	dummy_item.id = "test_apple"
	item_amount.item_def = dummy_item
	item_amount.count = 2
	def.stages[2].harvest_yields = [item_amount]

	var anchor := Vector3i(10, 0, 10)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	flora.set_growth_progress(1.0)

	var actor := Node3D.new()
	actor.position = flora.global_position + Vector3(2.0, 0.0, 0.0)
	_sandbox.container.add_child(actor)

	var success := flora.forage(actor)
	assert_bool(success).is_true()

	var items: Array[Node] = _sandbox.container.get_tree().get_nodes_in_group("world_items")
	var found_item: WorldItem = null
	for it in items:
		var wi := it as WorldItem
		if wi != null and is_instance_valid(wi) and wi.item_id == "test_apple":
			found_item = wi
			break

	assert_object(found_item).is_not_null()
	# Verify item is spawned offset towards actor in +X direction
	assert_float(found_item.position.x).is_greater(flora.global_position.x + 0.3)

	actor.free()


func test_can_chop_false_stage_blocks_take_damage() -> void:
	var def := _create_test_flora_def("test_uncoppable_stage")
	def.stages[2].can_chop = false
	var anchor := Vector3i(18, 0, 18)

	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	flora.set_growth_progress(1.0) # stage 2 -> can_chop false

	assert_bool(flora.can_be_felled()).is_false()
	flora.take_damage(9999)
	assert_int(flora.health_component.current_hp).is_equal(100)
	assert_bool(_furniture_layer.has_at(anchor)).is_true()


func test_can_chop_true_stage_allows_felling() -> void:
	var def := _create_test_flora_def("test_choppable_stage")
	var anchor := Vector3i(19, 0, 19)

	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	flora.set_growth_progress(1.0) # stage 2 -> can_chop true (default)

	assert_bool(flora.can_be_felled()).is_true()
	flora.take_damage(9999)
	assert_bool(_furniture_layer.has_at(anchor)).is_false()


func test_wild_flora_collider_scaling_and_grounded_position() -> void:
	var def := _create_test_flora_def("test_tree_collider")
	def.dimensions = Vector3i(1, 4, 1)
	def.stages[0].visual_scale = Vector3(0.2, 0.2, 0.2)
	def.stages[1].visual_scale = Vector3(0.6, 0.6, 0.6)
	def.stages[2].visual_scale = Vector3(1.0, 1.0, 1.0)

	var anchor := Vector3i(15, 0, 15)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	var build_shape := flora.get_node_or_null("BuildBody/BuildCollider") as CollisionShape3D
	assert_object(build_shape).is_not_null()

	# Stage 0: Sprout (scale 0.2) -> height = 0.8m, center Y = 0.4m
	flora.set_growth_progress(0.0)
	assert_float(build_shape.scale.y).is_equal_approx(0.2, 0.01)
	assert_float(build_shape.position.y).is_equal_approx(0.4, 0.01)

	# Stage 1: Young (scale 0.6) -> height = 2.4m, center Y = 1.2m
	flora.set_growth_progress(0.5)
	assert_float(build_shape.scale.y).is_equal_approx(0.6, 0.01)
	assert_float(build_shape.position.y).is_equal_approx(1.2, 0.01)

	# Stage 2: Mature (scale 1.0) -> height = 4.0m, center Y = 2.0m
	flora.set_growth_progress(1.0)
	assert_float(build_shape.scale.y).is_equal_approx(1.0, 0.01)
	assert_float(build_shape.position.y).is_equal_approx(2.0, 0.01)

