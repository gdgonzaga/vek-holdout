extends GdUnitTestSuite

## Unit tests for Furniture.get_footprint_cells (ARCH "Subsystem: Build"):
## the FurnitureDef multi-cell case (with yaw swap) and the non-FurnitureDef
## single-cell case — a Blueprint's def is the target's, so colonist job pathing
## reaches this with a BlockDef (wood-block blueprints crashed on def.dimensions
## before the corner-convention branch existed).

const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")

var _items: ItemDbSandbox


func before_test() -> void:
	_items = ItemDbSandbox.new(self)


func after_test() -> void:
	_items.restore()


func _make_furniture(def: BuildableDef) -> Furniture:
	var node: Furniture = auto_free(Furniture.new())
	add_child(node)
	node.def = def
	return node


func test_block_def_footprint_is_single_corner_cell() -> void:
	var def: BlockDef = auto_free(BlockDef.new())
	var node := _make_furniture(def)
	node.global_position = Vector3(2.0, 1.0, 3.0)
	var cells := node.get_footprint_cells()
	assert_int(cells.size()).is_equal(1)
	assert_bool(cells.has(Vector3i(2, 1, 3))).is_true()


func test_furniture_def_footprint_spans_dimensions() -> void:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.dimensions = Vector3i(2, 1, 2)
	var node := _make_furniture(def)
	# Footprint-center convention (FurnitureLayer.world_origin): a 2x2 footprint
	# anchored at (0,1,0) centres the node at (1,1,1).
	node.global_position = Vector3(1.0, 1.0, 1.0)
	var cells := node.get_footprint_cells()
	assert_int(cells.size()).is_equal(4)
	assert_bool(cells.has(Vector3i(0, 1, 0))).is_true()
	assert_bool(cells.has(Vector3i(1, 1, 1))).is_true()


func test_yaw_swaps_footprint_axes() -> void:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.dimensions = Vector3i(2, 1, 1)
	var node := _make_furniture(def)
	# world_origin(anchor (0,1,0), dims 2x1x1, yaw 1) -> centre (0.5, 1, 1).
	node.global_position = Vector3(0.5, 1.0, 1.0)
	node.rotation_degrees.y = 90.0
	var cells := node.get_footprint_cells()
	assert_int(cells.size()).is_equal(2)
	assert_bool(cells.has(Vector3i(0, 1, 0))).is_true()
	assert_bool(cells.has(Vector3i(0, 1, 1))).is_true()


func test_is_steppable_at_short_and_tall_furniture() -> void:
	var layer: FurnitureLayer = auto_free(FurnitureLayer.new())
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	layer.set_container(container)

	var short_def: FurnitureDef = auto_free(FurnitureDef.new())
	short_def.id = "trough"
	var short_mesh := BoxMesh.new()
	short_mesh.size = Vector3(1.0, 0.35, 1.0)
	short_def.mesh = short_mesh
	short_def.dimensions = Vector3i(1, 1, 1)

	var tall_def: FurnitureDef = auto_free(FurnitureDef.new())
	tall_def.id = "workbench"
	var tall_mesh := BoxMesh.new()
	tall_mesh.size = Vector3(1.0, 1.2, 1.0)
	tall_def.mesh = tall_mesh
	tall_def.dimensions = Vector3i(1, 1, 1)

	layer.spawn(short_def, Vector3i(0, 0, 0), 0)
	layer.spawn(tall_def, Vector3i(2, 0, 0), 0)

	assert_bool(layer.is_steppable_at(Vector3i(0, 0, 0), 0.5)).is_true()
	assert_bool(layer.is_steppable_at(Vector3i(0, 0, 0), 0.2)).is_false()
	assert_bool(layer.is_steppable_at(Vector3i(2, 0, 0), 0.5)).is_false()
	assert_bool(layer.is_steppable_at(Vector3i(5, 0, 0), 0.5)).is_false()


func test_shelf1_and_storage_crate_unlocked_by_default() -> void:
	assert_bool(BuildLibrary.has_def("shelf1")).is_true()
	var shelf_def := BuildLibrary.get_def("shelf1")
	assert_bool(shelf_def.unlocked_by_default).is_true()
	assert_bool(BuildLibrary.is_unlocked("shelf1")).is_true()

	assert_bool(BuildLibrary.has_def("storage_crate")).is_true()
	var crate_def := BuildLibrary.get_def("storage_crate")
	assert_bool(crate_def.unlocked_by_default).is_true()
	assert_bool(BuildLibrary.is_unlocked("storage_crate")).is_true()
func test_furniture_layer_instantiates_scene_when_provided() -> void:
	var layer: FurnitureLayer = auto_free(FurnitureLayer.new())
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	layer.set_container(container)

	var scene_root := Node3D.new()
	scene_root.name = "CustomSceneRoot"
	var mi := MeshInstance3D.new()
	mi.name = "VisualPart"
	mi.mesh = BoxMesh.new()
	scene_root.add_child(mi)
	mi.owner = scene_root
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	scene_root.add_child(muzzle)
	muzzle.owner = scene_root

	var packed := PackedScene.new()
	packed.pack(scene_root)
	scene_root.free()

	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_scene_furniture"
	def.scene = packed
	def.dimensions = Vector3i.ONE

	var node := layer.spawn(def, Vector3i(1, 0, 1), 0)
	assert_object(node).is_not_null()
	assert_object(node.find_child("CustomSceneRoot", true, false)).is_not_null()
	assert_object(node.find_child("Muzzle", true, false)).is_not_null()


func test_blueprint_layer_instantiates_scene_hologram_when_provided() -> void:
	var layer: BlueprintLayer = auto_free(BlueprintLayer.new())
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	layer.set_container(container)

	var scene_root := Node3D.new()
	scene_root.name = "BlueprintSceneRoot"
	var mi := MeshInstance3D.new()
	mi.name = "HoloMesh"
	mi.mesh = BoxMesh.new()
	scene_root.add_child(mi)
	mi.owner = scene_root

	var packed := PackedScene.new()
	packed.pack(scene_root)
	scene_root.free()

	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_bp_scene"
	def.scene = packed
	def.dimensions = Vector3i.ONE

	var node: Blueprint = layer.spawn_blueprint(def, Vector3i(2, 0, 2), 0)
	assert_object(node).is_not_null()
	assert_object(node.find_child("BlueprintSceneRoot", true, false)).is_not_null()
	var holo_mi := node.find_child("HoloMesh", true, false) as MeshInstance3D
	assert_object(holo_mi).is_not_null()
	assert_object(holo_mi.material_override).is_not_null()


func test_furniture_layer_attaches_light_source_component_when_light_params_present() -> void:
	var layer: FurnitureLayer = auto_free(FurnitureLayer.new())
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	layer.set_container(container)

	var light_params: LightParams = auto_free(LightParams.new())
	light_params.color = Color(1.0, 0.5, 0.0, 1.0)
	light_params.energy = 2.5
	light_params.range = 10.0
	light_params.attenuation = 0.8
	light_params.shadows_enabled = true
	light_params.local_offset = Vector3(0.0, 2.0, 0.0)

	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_lamp"
	def.mesh = BoxMesh.new()
	def.dimensions = Vector3i.ONE
	def.light_params = light_params

	var node: Furniture = layer.spawn(def, Vector3i(0, 0, 0), 0)
	assert_object(node).is_not_null()

	var component := node.get_node_or_null("LightSourceComponent") as LightSourceComponent
	assert_object(component).is_not_null()
	assert_object(component.params).is_equal(light_params)

	var light := component.get_light_node()
	assert_object(light).is_not_null()
	assert_float(light.light_energy).is_equal_approx(2.5, 0.01)
	assert_float(light.omni_range).is_equal_approx(10.0, 0.01)
	assert_bool(light.shadow_enabled).is_true()
	assert_vector(light.position).is_equal(Vector3(0.0, 2.0, 0.0))


func test_furniture_layer_attaches_bed_component_when_bed_params_present() -> void:
	var layer: FurnitureLayer = auto_free(FurnitureLayer.new())
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	layer.set_container(container)

	var bparams: BedParams = auto_free(BedParams.new())
	bparams.sleep_offset = Vector3(0.1, 0.2, 0.3)
	bparams.rest_per_game_hour = 0.25

	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_bed"
	def.mesh = BoxMesh.new()
	def.dimensions = Vector3i(1, 1, 2)
	def.tags = ["bed"]
	def.bed_params = bparams

	var node: Furniture = layer.spawn(def, Vector3i(0, 0, 0), 0)
	assert_object(node).is_not_null()

	var bed_comp := node.get_node_or_null("BedComponent") as BedComponent
	assert_object(bed_comp).is_not_null()
	assert_bool(bed_comp.is_available()).is_true()
	assert_object(bed_comp.params()).is_equal(bparams)
	assert_float(bed_comp.params().rest_per_game_hour).is_equal_approx(0.25, 0.01)


func test_furniture_get_capability_and_iter_capabilities() -> void:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	var bparams: BedParams = auto_free(BedParams.new())
	var lparams: LightParams = auto_free(LightParams.new())
	def.bed_params = bparams
	def.light_params = lparams

	var node: Furniture = auto_free(Furniture.new())
	node.def = def

	var found_bed := Furniture.get_capability(node, BedParams)
	assert_object(found_bed).is_equal(bparams)

	var found_light := Furniture.get_capability(node, LightParams)
	assert_object(found_light).is_equal(lparams)

	var not_found := Furniture.get_capability(node, StorageParams)
	assert_object(not_found).is_null()

	var caps := FurnitureLayer._iter_capabilities(def)
	assert_int(caps.size()).is_equal(2)


func test_furniture_serialize_deserialize_round_trips_storage_contents() -> void:
	var layer: FurnitureLayer = auto_free(FurnitureLayer.new())
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	layer.set_container(container)

	# Synthetic item only: the suite never reads shipped item content.
	_items.add_item("test_scrap")

	var sparams: StorageParams = auto_free(StorageParams.new())
	sparams.capacity = 50.0

	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_crate"
	def.mesh = BoxMesh.new()
	def.storage_params = sparams

	var node: Furniture = layer.spawn(def, Vector3i(0, 0, 0), 0)
	assert_object(node).is_not_null()

	var storage := node.get_node_or_null("StorageInventory") as StorageInventory
	assert_object(storage).is_not_null()
	storage.set_priority(4)
	storage.set_item_allowed("test_scrap", true)
	assert_int(storage.add("test_scrap", 6)).is_equal(0)

	# 1. Serialize: contents live only under cap_state["StorageInventory"] —
	# the legacy "storage" key is gone (Hard rule 10, D2 breaking change).
	var snapshot := node.serialize()
	assert_bool(snapshot.has("cap_state")).is_true()
	assert_bool(snapshot.has("storage")).is_false()
	var cap_state: Dictionary = snapshot["cap_state"]
	assert_bool(cap_state.has("StorageInventory")).is_true()

	# 2. Deserialize into a fresh furniture instance: restores priority, the
	# item filter whitelist and the item stacks from cap_state alone.
	var fresh_def: FurnitureDef = auto_free(FurnitureDef.new())
	fresh_def.id = "test_crate"
	fresh_def.mesh = BoxMesh.new()
	fresh_def.storage_params = sparams
	var fresh_node: Furniture = layer.spawn(fresh_def, Vector3i(2, 0, 0), 0)
	var fresh_storage := fresh_node.get_node_or_null("StorageInventory") as StorageInventory
	assert_object(fresh_storage).is_not_null()

	fresh_node.deserialize(snapshot)
	assert_int(fresh_storage.priority).is_equal(4)
	assert_bool(fresh_storage.allowed_item_ids.has("test_scrap")).is_true()
	assert_int(fresh_storage.get_item_count("test_scrap")).is_equal(6)


func test_furniture_group_registration() -> void:
	var furniture: Furniture = auto_free(preload("res://subsystems/furniture/furniture.gd").new()) as Furniture
	furniture.def_id = "test_bed"
	furniture._ready()
	assert_bool(furniture.is_in_group(&"test_bed")).is_true()
	assert_bool(furniture.is_in_group(&"furniture")).is_true()
