extends GdUnitTestSuite

## Unit tests for Furniture.get_footprint_cells (ARCH "Subsystem: Build"):
## the FurnitureDef multi-cell case (with yaw swap) and the non-FurnitureDef
## single-cell case — a Blueprint's def is the target's, so colonist job pathing
## reaches this with a BlockDef (wood-block blueprints crashed on def.dimensions
## before the corner-convention branch existed).

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
