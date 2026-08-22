extends GdUnitTestSuite

## Tests for rotatable block placement via InstantPlacementStrategy and BlueprintLayer,
## verifying that yaw steps (0..3) map to orthogonal rotation indices ([0, 22, 10, 16])
## and that blueprint meshes rotate around the cell center without offset.

class MockRecordingVoxelGridAdapter extends VoxelGridAdapter:
	var placed_blocks: Array = []

	func set_block_at(pos: Vector3i, block_id: String, rot_index: int = 0) -> void:
		placed_blocks.append({"pos": pos, "block_id": block_id, "rot_index": rot_index})

	func is_valid_placement(_pos: Vector3i) -> bool:
		return true


func test_instant_placement_strategy_wood_stairs_rotations() -> void:
	var grid: MockRecordingVoxelGridAdapter = auto_free(MockRecordingVoxelGridAdapter.new())
	var strategy := InstantPlacementStrategy.new()
	strategy.set_grid(grid)

	var def: BuildableDef = BuildLibrary.get_def("wood_stairs")
	assert_object(def).is_not_null()

	var rot_state := RotationState.new()
	# Step 0 (0 deg) -> ortho index 0
	rot_state.step = 0
	var t0 := Transform3D.IDENTITY
	t0.origin = Vector3(1, 2, 3)
	assert_bool(strategy.commit(t0, rot_state, "wood_stairs")).is_true()
	assert_int(grid.placed_blocks.size()).is_equal(1)
	assert_that(grid.placed_blocks[0]["pos"]).is_equal(Vector3i(1, 2, 3))
	assert_str(grid.placed_blocks[0]["block_id"]).is_equal("wood_stairs")
	assert_int(grid.placed_blocks[0]["rot_index"]).is_equal(BlockDef.YAW_INDICES[0])

	# Step 1 (90 deg) -> ortho index 22
	rot_state.step = 1
	var t1 := Transform3D.IDENTITY
	t1.origin = Vector3(4, 2, 5)
	assert_bool(strategy.commit(t1, rot_state, "wood_stairs")).is_true()
	assert_int(grid.placed_blocks.size()).is_equal(2)
	assert_that(grid.placed_blocks[1]["pos"]).is_equal(Vector3i(4, 2, 5))
	assert_int(grid.placed_blocks[1]["rot_index"]).is_equal(BlockDef.YAW_INDICES[1])

	# Step 2 (180 deg) -> ortho index 10
	rot_state.step = 2
	var t2 := Transform3D.IDENTITY
	t2.origin = Vector3(7, 2, 8)
	assert_bool(strategy.commit(t2, rot_state, "wood_stairs")).is_true()
	assert_int(grid.placed_blocks.size()).is_equal(3)
	assert_int(grid.placed_blocks[2]["rot_index"]).is_equal(BlockDef.YAW_INDICES[2])

	# Step 3 (270 deg) -> ortho index 16
	rot_state.step = 3
	var t3 := Transform3D.IDENTITY
	t3.origin = Vector3(9, 2, 10)
	assert_bool(strategy.commit(t3, rot_state, "wood_stairs")).is_true()
	assert_int(grid.placed_blocks.size()).is_equal(4)
	assert_int(grid.placed_blocks[3]["rot_index"]).is_equal(BlockDef.YAW_INDICES[3])


func test_blueprint_layer_block_mesh_centered_in_cell() -> void:
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)

	var layer := BlueprintLayer.new()
	layer.set_container(container)

	var def: BuildableDef = BuildLibrary.get_def("wood_stairs")
	assert_object(def).is_not_null()

	# Spawn blueprint at anchor (5, 0, 5) with step 2 (180 deg)
	var bp: Blueprint = layer.spawn_blueprint(def, Vector3i(5, 0, 5), 2)
	assert_object(bp).is_not_null()
	auto_free(bp)

	# Global position of blueprint root is at the anchor cell corner
	assert_that(bp.global_position).is_equal(Vector3(5, 0, 5))

	# Mesh child node is centered so that rotated vertices stay within [0, 1]^3
	var mesh_node: MeshInstance3D = bp.find_child("Mesh")
	assert_object(mesh_node).is_not_null()
	# At 180 deg yaw, local mesh position is (1, 0, 1) and basis is -X, Y, -Z
	assert_bool(mesh_node.position.is_equal_approx(Vector3(1, 0, 1))).is_true()
	var expected_basis := Basis(Vector3.UP, PI)
	assert_bool(mesh_node.transform.basis.is_equal_approx(expected_basis)).is_true()

	# Build collider stays centered at (0.5, 0.5, 0.5) in local space
	var collider: CollisionShape3D = bp.get_node("BuildBody/BuildCollider")
	assert_object(collider).is_not_null()
	assert_that(collider.position).is_equal(Vector3(0.5, 0.5, 0.5))


func test_blueprint_completion_forwards_rotation_to_grid() -> void:
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)

	var grid: MockRecordingVoxelGridAdapter = auto_free(MockRecordingVoxelGridAdapter.new())
	var layer := BlueprintLayer.new()
	layer.set_container(container)
	layer.set_grid(grid)

	var def: BuildableDef = BuildLibrary.get_def("wood_stairs")
	assert_object(def).is_not_null()

	# Spawn blueprint at anchor (3, 1, 3) with step 1 (90 deg)
	var bp: Blueprint = layer.spawn_blueprint(def, Vector3i(3, 1, 3), 1)
	assert_object(bp).is_not_null()

	# Complete blueprint
	assert_bool(layer.complete_blueprint(bp)).is_true()
	assert_int(grid.placed_blocks.size()).is_equal(1)
	assert_that(grid.placed_blocks[0]["pos"]).is_equal(Vector3i(3, 1, 3))
	assert_str(grid.placed_blocks[0]["block_id"]).is_equal("wood_stairs")
	assert_int(grid.placed_blocks[0]["rot_index"]).is_equal(BlockDef.YAW_INDICES[1])
