extends GdUnitTestSuite

class MockBlockGrid extends IBlockGrid:
	var last_set_pos: Vector3i = Vector3i.ZERO
	var last_set_type_id: int = -1
	var last_set_rot_index: int = -1

	func set_block(pos: Vector3i, type_id: int, rot_index: int = 0) -> void:
		last_set_pos = pos
		last_set_type_id = type_id
		last_set_rot_index = rot_index


func test_set_active_block_def_resets_rotation() -> void:
	var controller: BlockPlacementController = auto_free(BlockPlacementController.new()) as BlockPlacementController
	var preview: Node3D = auto_free(Node3D.new()) as Node3D
	controller._preview_node = preview

	var def_3d: BlockDef = auto_free(BlockDef.new()) as BlockDef
	def_3d.rotation_mode = BlockDef.RotationMode.FULL_3D
	def_3d.type_id = 10

	controller.set_active_block_def(def_3d)
	assert_int(controller._current_rot_index).is_equal(0)
	assert_object(controller._current_block_def).is_equal(def_3d)
	assert_bool(preview.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()


func test_full_3d_rotation_yaw_pitch_roll() -> void:
	var controller: BlockPlacementController = auto_free(BlockPlacementController.new()) as BlockPlacementController
	var preview: Node3D = auto_free(Node3D.new()) as Node3D
	controller._preview_node = preview

	var def_3d: BlockDef = auto_free(BlockDef.new()) as BlockDef
	def_3d.rotation_mode = BlockDef.RotationMode.FULL_3D
	def_3d.type_id = 5

	controller.set_active_block_def(def_3d)

	# Rotate yaw (Vector3.UP)
	controller.rotate_axis(Vector3.UP, 1)
	assert_int(controller._current_rot_index).is_not_equal(0)
	assert_bool(preview.transform.basis.is_equal_approx(VoxelBlockEncoder.rot_index_to_basis(controller._current_rot_index))).is_true()

	# Rotate pitch (Vector3.RIGHT)
	controller.rotate_axis(Vector3.RIGHT, 1)
	assert_bool(preview.transform.basis.is_equal_approx(VoxelBlockEncoder.rot_index_to_basis(controller._current_rot_index))).is_true()

	# Rotate roll (Vector3.FORWARD)
	controller.rotate_axis(Vector3.FORWARD, 1)
	assert_bool(preview.transform.basis.is_equal_approx(VoxelBlockEncoder.rot_index_to_basis(controller._current_rot_index))).is_true()

	# reset_rotation returns to identity
	controller.reset_rotation()
	assert_int(controller._current_rot_index).is_equal(0)
	assert_bool(preview.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()


func test_none_rotation_mode_ignores_rotation() -> void:
	var controller: BlockPlacementController = auto_free(BlockPlacementController.new()) as BlockPlacementController
	var preview: Node3D = auto_free(Node3D.new()) as Node3D
	controller._preview_node = preview

	var def_none: BlockDef = auto_free(BlockDef.new()) as BlockDef
	def_none.rotation_mode = BlockDef.RotationMode.NONE
	def_none.type_id = 2

	controller.set_active_block_def(def_none)

	# Rotation inputs should be ignored
	controller.rotate_axis(Vector3.UP, 1)
	assert_int(controller._current_rot_index).is_equal(0)
	assert_bool(preview.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()

	controller.rotate_axis(Vector3.RIGHT, 1)
	assert_int(controller._current_rot_index).is_equal(0)
	assert_bool(preview.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()

	controller.rotate_axis(Vector3.FORWARD, 1)
	assert_int(controller._current_rot_index).is_equal(0)
	assert_bool(preview.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()

	# Placement commit always uses rot_index = 0
	var mock_grid: MockBlockGrid = auto_free(MockBlockGrid.new()) as MockBlockGrid
	controller.commit_placement(Vector3i(1, 2, 3), mock_grid)
	assert_int(mock_grid.last_set_type_id).is_equal(2)
	assert_int(mock_grid.last_set_rot_index).is_equal(0)
	assert_vector(mock_grid.last_set_pos).is_equal(Vector3i(1, 2, 3))


func test_commit_placement_with_rotation() -> void:
	var controller: BlockPlacementController = auto_free(BlockPlacementController.new()) as BlockPlacementController
	var def_3d: BlockDef = auto_free(BlockDef.new()) as BlockDef
	def_3d.rotation_mode = BlockDef.RotationMode.FULL_3D
	def_3d.type_id = 42

	controller.set_active_block_def(def_3d)
	controller.rotate_axis(Vector3.UP, 1)

	var target_rot: int = controller._current_rot_index
	var mock_grid: MockBlockGrid = auto_free(MockBlockGrid.new()) as MockBlockGrid
	controller.commit_placement(Vector3i(5, 10, -2), mock_grid)

	assert_int(mock_grid.last_set_type_id).is_equal(42)
	assert_int(mock_grid.last_set_rot_index).is_equal(target_rot)
	assert_vector(mock_grid.last_set_pos).is_equal(Vector3i(5, 10, -2))


func test_unhandled_input_rotation_and_uigate_blocked() -> void:
	var controller: BlockPlacementController = auto_free(BlockPlacementController.new()) as BlockPlacementController
	var preview: Node3D = auto_free(Node3D.new()) as Node3D
	controller._preview_node = preview

	var def_3d: BlockDef = auto_free(BlockDef.new()) as BlockDef
	def_3d.rotation_mode = BlockDef.RotationMode.FULL_3D
	def_3d.type_id = 7
	controller.set_active_block_def(def_3d)

	var prev_rot: int = controller._current_rot_index

	# Simulate UiGate input block
	var dummy_modal: Control = auto_free(Control.new()) as Control
	UiGate.open_modal(dummy_modal)

	var event_pitch: InputEventKey = InputEventKey.new()
	event_pitch.keycode = KEY_R
	event_pitch.shift_pressed = true
	event_pitch.pressed = true

	controller._unhandled_input(event_pitch)
	assert_int(controller._current_rot_index).is_equal(prev_rot)

	UiGate.close_modal(dummy_modal)
