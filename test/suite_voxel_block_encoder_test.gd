extends GdUnitTestSuite

func test_encode_decode_roundtrip() -> void:
	var test_cases: Array[Array] = [
		[0, 0],
		[1, 0],
		[1, 5],
		[42, 17],
		[2047, 23],
		[512, 31],
	]
	for tc in test_cases:
		var type_id: int = tc[0]
		var rot_index: int = tc[1]
		var raw: int = VoxelBlockEncoder.encode(type_id, rot_index)
		assert_int(VoxelBlockEncoder.decode_type(raw)).is_equal(type_id)
		assert_int(VoxelBlockEncoder.decode_rotation(raw)).is_equal(rot_index & VoxelBlockEncoder.ROTATION_MASK)


func test_basis_rot_index_fidelity_all_24_states() -> void:
	for i in range(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS):
		var b := VoxelBlockEncoder.rot_index_to_basis(i)
		var recovered_idx := VoxelBlockEncoder.basis_to_rot_index(b)
		assert_int(recovered_idx).is_equal(i)


func test_rot_index_clamping() -> void:
	var b_neg := VoxelBlockEncoder.rot_index_to_basis(-5)
	assert_int(VoxelBlockEncoder.basis_to_rot_index(b_neg)).is_equal(0)
	
	var b_over := VoxelBlockEncoder.rot_index_to_basis(100)
	assert_int(VoxelBlockEncoder.basis_to_rot_index(b_over)).is_equal(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS - 1)


func test_rotate_around_axis_90_deg_steps() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]
	for axis in axes:
		var curr := 0
		for step in range(4):
			curr = VoxelBlockEncoder.rotate_around_axis(curr, axis, PI / 2.0)
			assert_int(curr).is_greater_equal(0)
			assert_int(curr).is_less(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS)
		# 4x 90-degree rotations around any primary axis returns to original rotation state
		assert_int(curr).is_equal(0)
