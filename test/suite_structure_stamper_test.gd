extends GdUnitTestSuite

## Unit tests for StructureStamper (ARCH "Map Authoring" / "Build").
## Tests pivot offset calculation, discrete 90-degree Y rotation,
## voxel coordinate transformation, and stamping of BLOCK, SMOOTH_TERRAIN, AIR, and IGNORE voxels.

const Doubles = preload("res://test/helpers/doubles.gd")
const StructureStamper = preload("res://subsystems/map_authoring/structure_stamper.gd")


class MockVoxelGridAdapter extends VoxelGridAdapter:
	var placed_blocks: Dictionary = {}
	var raw_voxels: Dictionary = {}

	func get_block_at(pos: Vector3i) -> String:
		return placed_blocks.get(pos, "")

	func set_block_at(pos: Vector3i, block_id: String) -> void:
		placed_blocks[pos] = block_id

	func remove_block_at(pos: Vector3i) -> void:
		placed_blocks.erase(pos)

	func get_raw_voxel(pos: Vector3i) -> int:
		return raw_voxels.get(pos, 0)

	func set_raw_voxel(pos: Vector3i, raw_val: int) -> void:
		raw_voxels[pos] = raw_val


func _create_sample_vox_data() -> VoxData:
	var data: VoxData = auto_free(VoxData.new())
	data.dimensions = Vector3i(3, 2, 3)
	data.palette = [Color.BLACK]
	for i in range(255):
		data.palette.append(Color.WHITE)
	data.palette[1] = Color(1, 0, 0, 1) # Red
	data.palette[2] = Color(0, 1, 0, 1) # Green
	data.palette[3] = Color(0, 0, 1, 1) # Blue
	data.palette[4] = Color(1, 1, 0, 1) # Yellow

	# Place voxels:
	# Local center bottom (1, 0, 1) -> Color 1 (Red)
	data.set_voxel(Vector3i(1, 0, 1), 1)
	# Local corner (0, 0, 0) -> Color 2 (Green)
	data.set_voxel(Vector3i(0, 0, 0), 2)
	# Local top center (1, 1, 1) -> Color 3 (Blue)
	data.set_voxel(Vector3i(1, 1, 1), 3)
	# Local edge (2, 0, 1) -> Color 4 (Yellow)
	data.set_voxel(Vector3i(2, 0, 1), 4)

	return data


func _create_sample_mapping() -> VoxPaletteMapping:
	var mapping: VoxPaletteMapping = auto_free(VoxPaletteMapping.new())
	mapping.id = "test_mapping"
	mapping.display_name = "Test Mapping"

	var e1: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e1.source_index = 1
	e1.target_type = VoxPaletteEntry.TargetType.BLOCK
	e1.block_id = "stone_wall"

	var e2: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e2.source_index = 2
	e2.target_type = VoxPaletteEntry.TargetType.SMOOTH_TERRAIN
	e2.terrain_material_id = "rock42"

	var e3: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e3.source_index = 3
	e3.target_type = VoxPaletteEntry.TargetType.AIR

	var e4: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e4.source_index = 4
	e4.target_type = VoxPaletteEntry.TargetType.IGNORE

	mapping.entries = [e1, e2, e3, e4]
	return mapping


func _create_sample_structure(mapping: VoxPaletteMapping) -> StructureDef:
	var def: StructureDef = auto_free(StructureDef.new())
	def.id = "test_structure"
	def.display_name = "Test Structure"
	def.palette_mapping = mapping
	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CENTER
	def.custom_pivot_offset = Vector3i.ZERO
	def.bounding_box_size = Vector3i(3, 2, 3)
	return def


func test_calculate_pivot_offset() -> void:
	var def: StructureDef = auto_free(StructureDef.new())
	def.bounding_box_size = Vector3i(6, 4, 8)

	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CENTER
	assert_vector(StructureStamper.calculate_pivot_offset(def)).is_equal(Vector3i(3, 0, 4))

	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CORNER
	assert_vector(StructureStamper.calculate_pivot_offset(def)).is_equal(Vector3i(0, 0, 0))

	def.pivot_anchor = StructureDef.PivotAnchor.GEOMETRIC_CENTER
	assert_vector(StructureStamper.calculate_pivot_offset(def)).is_equal(Vector3i(3, 2, 4))

	def.pivot_anchor = StructureDef.PivotAnchor.CUSTOM
	def.custom_pivot_offset = Vector3i(1, 2, 3)
	assert_vector(StructureStamper.calculate_pivot_offset(def)).is_equal(Vector3i(1, 2, 3))

	# With custom offset added to BOTTOM_CENTER
	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CENTER
	def.custom_pivot_offset = Vector3i(1, -1, 2)
	assert_vector(StructureStamper.calculate_pivot_offset(def)).is_equal(Vector3i(4, -1, 6))

	# Private alias test
	var vox_data: VoxData = auto_free(VoxData.new())
	vox_data.dimensions = Vector3i(10, 10, 10)
	def.custom_pivot_offset = Vector3i.ZERO
	assert_vector(StructureStamper._calculate_pivot_offset(def, vox_data)).is_equal(Vector3i(5, 0, 5))


func test_rotate_vector_y() -> void:
	var v := Vector3i(1, 2, 3)

	# 0 degrees
	assert_vector(StructureStamper.rotate_vector_y(v, 0)).is_equal(Vector3i(1, 2, 3))
	assert_vector(StructureStamper.rotate_vector_y(v, 4)).is_equal(Vector3i(1, 2, 3))

	# 90 degrees (+Y rotation: (x,y,z) -> (z, y, -x))
	assert_vector(StructureStamper.rotate_vector_y(v, 1)).is_equal(Vector3i(3, 2, -1))

	# 180 degrees (+Y rotation: (x,y,z) -> (-x, y, -z))
	assert_vector(StructureStamper.rotate_vector_y(v, 2)).is_equal(Vector3i(-1, 2, -3))

	# 270 degrees (+Y rotation: (x,y,z) -> (-z, y, x))
	assert_vector(StructureStamper.rotate_vector_y(v, 3)).is_equal(Vector3i(-3, 2, 1))

	# Negative rotations
	assert_vector(StructureStamper.rotate_vector_y(v, -1)).is_equal(Vector3i(-3, 2, 1))
	assert_vector(StructureStamper.rotate_vector_y(v, -2)).is_equal(Vector3i(-1, 2, -3))


func test_get_transformed_voxels() -> void:
	var vox_data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var structure := _create_sample_structure(mapping)

	# Pivot is at (1, 0, 1) for 3x2x3 with BOTTOM_CENTER
	var origin := Vector3i(10, 20, 30)

	# Unrotated (0 steps)
	var transformed := StructureStamper.get_transformed_voxels(structure, vox_data, origin, 0)
	assert_int(transformed.size()).is_equal(4)

	var world_map: Dictionary = {}
	for item in transformed:
		world_map[item["local_pos"]] = item

	# Center bottom (1, 0, 1) rel_pos (0,0,0) -> world (10, 20, 30)
	assert_vector(world_map[Vector3i(1, 0, 1)]["world_pos"]).is_equal(Vector3i(10, 20, 30))
	assert_str(world_map[Vector3i(1, 0, 1)]["target_entry"].block_id).is_equal("stone_wall")

	# Corner (0, 0, 0) rel_pos (-1, 0, -1) -> world (9, 20, 29)
	assert_vector(world_map[Vector3i(0, 0, 0)]["world_pos"]).is_equal(Vector3i(9, 20, 29))
	assert_str(world_map[Vector3i(0, 0, 0)]["target_entry"].terrain_material_id).is_equal("rock42")

	# Rotated 90 degrees (1 step)
	var transformed_rot := StructureStamper.get_transformed_voxels(structure, vox_data, origin, 1)
	var world_map_rot: Dictionary = {}
	for item in transformed_rot:
		world_map_rot[item["local_pos"]] = item

	# Center bottom (1, 0, 1) rel_pos (0,0,0) -> rotated (0,0,0) -> world (10, 20, 30)
	assert_vector(world_map_rot[Vector3i(1, 0, 1)]["world_pos"]).is_equal(Vector3i(10, 20, 30))

	# Corner (0, 0, 0) rel_pos (-1, 0, -1) -> rotated (-1, 0, 1) -> world (9, 20, 31)
	assert_vector(world_map_rot[Vector3i(0, 0, 0)]["world_pos"]).is_equal(Vector3i(9, 20, 31))


func test_stamp_structure_all_types() -> void:
	var vox_data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var structure := _create_sample_structure(mapping)

	var grid: MockVoxelGridAdapter = auto_free(MockVoxelGridAdapter.new())
	var smooth_grid: Doubles.RecordingSmoothGrid = auto_free(Doubles.RecordingSmoothGrid.new())
	grid.set_smooth_grid(smooth_grid)

	# Pre-populate existing blocks
	grid.set_block_at(Vector3i(10, 21, 30), "existing_block") # Where blue AIR voxel will land

	var origin := Vector3i(10, 20, 30)
	var ops := StructureStamper.stamp_structure(grid, structure, vox_data, origin, 0)

	# 1. BLOCK: Red voxel at (1, 0, 1) -> world (10, 20, 30) -> stone_wall
	assert_str(grid.get_block_at(Vector3i(10, 20, 30))).is_equal("stone_wall")

	# 2. SMOOTH_TERRAIN: Green voxel at (0, 0, 0) -> world (9, 20, 29) -> smooth_grid.adds
	assert_int(smooth_grid.adds.size()).is_equal(1)
	assert_that(smooth_grid.adds[0]["pos"]).is_equal(Vector3(9.5, 20.5, 29.5))
	assert_str(smooth_grid.adds[0]["material_id"]).is_equal("rock42")

	# 3. AIR: Blue voxel at (1, 1, 1) -> world (10, 21, 30) -> removed from grid and carved smooth terrain
	assert_str(grid.get_block_at(Vector3i(10, 21, 30))).is_equal("")
	assert_int(smooth_grid.carves.size()).is_equal(1)
	assert_that(smooth_grid.carves[0]["pos"]).is_equal(Vector3(10.5, 21.5, 30.5))

	# 4. IGNORE: Yellow voxel at (2, 0, 1) -> world (11, 20, 30) -> no modification
	assert_str(grid.get_block_at(Vector3i(11, 20, 30))).is_equal("")

	# Verify ops record size
	assert_int(ops.size()).is_equal(3) # BLOCK, SMOOTH_TERRAIN, AIR


func test_calculate_bounding_box() -> void:
	var vox_data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var structure := _create_sample_structure(mapping)

	var origin := Vector3i(10, 20, 30)
	var aabb_unrot := StructureStamper.calculate_bounding_box(structure, vox_data, origin, 0)
	assert_float(aabb_unrot.position.x).is_equal_approx(9.0, 0.001)
	assert_float(aabb_unrot.position.y).is_equal_approx(20.0, 0.001)
	assert_float(aabb_unrot.position.z).is_equal_approx(29.0, 0.001)
	assert_float(aabb_unrot.end.x).is_equal_approx(12.0, 0.001)
	assert_float(aabb_unrot.end.y).is_equal_approx(22.0, 0.001)
	assert_float(aabb_unrot.end.z).is_equal_approx(31.0, 0.001)


func test_stamp_structure_null_safe() -> void:
	var vox_data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var structure := _create_sample_structure(mapping)
	var grid: MockVoxelGridAdapter = auto_free(MockVoxelGridAdapter.new())

	# Null grid
	var ops1 := StructureStamper.stamp_structure(null, structure, vox_data, Vector3i.ZERO)
	assert_int(ops1.size()).is_equal(0)

	# Null structure
	var ops2 := StructureStamper.stamp_structure(grid, null, vox_data, Vector3i.ZERO)
	assert_int(ops2.size()).is_equal(0)

	# Null vox_data
	var ops3 := StructureStamper.stamp_structure(grid, structure, null, Vector3i.ZERO)
	assert_int(ops3.size()).is_equal(0)
