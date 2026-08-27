extends GdUnitTestSuite

## Rotation-variant baking in BlockLibrary: base table stability for shipped
## content, variant appendix layout for rotatable defs, stored-index
## resolution round-trips, and a mesher-level regression that variant indices
## actually render rotated geometry.

const Fixtures := preload("res://test/helpers/rotation_fixtures.gd")


## Fixture dir (plain NONE, yawwedge YAW_ONLY, fullwedge FULL_3D): base
## table stays 0..3, variants are appended after it — 3 yaw + 23 full = 30.
func test_variants_are_baked_after_the_base_table() -> void:
	var dir := Fixtures.make_block_dir("layout")
	var lib := BlockLibrary.new(dir)
	assert_int(lib.get_index("plain")).is_equal(1)
	assert_int(lib.get_index("yawwedge")).is_equal(2)
	assert_int(lib.get_index("fullwedge")).is_equal(3)
	assert_int(lib.get_voxel_library().get_models().size()).is_equal(1 + 3 + 3 + 23)


func test_stored_index_resolution_yaw_roundtrip() -> void:
	var dir := Fixtures.make_block_dir("yawrt")
	var lib := BlockLibrary.new(dir)
	var yaw_base := lib.get_index("yawwedge")

	# Rotation 0 stores the base index itself.
	assert_int(lib.get_stored_index(yaw_base, 0)).is_equal(yaw_base)
	# NONE defs ignore rotation entirely.
	assert_int(lib.get_stored_index(lib.get_index("plain"), 22)).is_equal(lib.get_index("plain"))
	# A tilt snaps to a valid yaw (4 -> 0 deg), still storing a valid index.
	assert_int(lib.get_rotation_index(lib.get_stored_index(yaw_base, 4))).is_equal(0)

	# Each quarter-turn resolves to a distinct variant that decodes back.
	var stored_values := {}
	for k in range(4):
		var stored := lib.get_stored_index(yaw_base, k)
		if k == 0:
			assert_int(stored).is_equal(yaw_base)
		else:
			assert_int(stored).is_not_equal(yaw_base)
		assert_bool(stored_values.has(stored)).is_false()
		stored_values[stored] = true
		assert_int(lib.get_base_index(stored)).is_equal(yaw_base)
		assert_int(lib.get_rotation_index(stored)).is_equal(BlockDef.YAW_INDICES[k])
		assert_str(lib.get_id(stored)).is_equal("yawwedge")
		assert_object(lib.get_def_by_index(stored)).is_equal(lib.get_def("yawwedge"))


func test_stored_index_resolution_full_3d_roundtrip() -> void:
	var dir := Fixtures.make_block_dir("fullrt")
	var lib := BlockLibrary.new(dir)
	var full_base := lib.get_index("fullwedge")

	for ortho in range(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS):
		var stored := lib.get_stored_index(full_base, ortho)
		if ortho == 0:
			assert_int(stored).is_equal(full_base)
		else:
			assert_int(stored).is_not_equal(full_base)
		assert_int(lib.get_base_index(stored)).is_equal(full_base)
		assert_int(lib.get_rotation_index(stored)).is_equal(ortho)


## Unknown indices pass through defensively (corrupt/foreign stored values
## must not crash resolution or masquerade as variants).
func test_unknown_indices_pass_through() -> void:
	var dir := Fixtures.make_block_dir("unknown")
	var lib := BlockLibrary.new(dir)
	assert_int(lib.get_stored_index(99, 5)).is_equal(99)
	assert_int(lib.get_base_index(99)).is_equal(99)
	assert_int(lib.get_rotation_index(99)).is_equal(0)
	assert_str(lib.get_id(99)).is_equal("")


## The whole point of the mechanism: a stored VARIANT index renders the
## def's single mesh rotated by the encoder's basis for that orientation
## (quarter turn about the cell center) — variants share the def's mesh.
func test_variant_indices_render_rotated_geometry() -> void:
	var dir := Fixtures.make_block_dir("render")
	var lib := BlockLibrary.new(dir)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = lib.get_voxel_library()
	var yaw_base := lib.get_index("yawwedge")

	var base_verts := _render_vertex_set(mesher, yaw_base)
	assert_int(base_verts.size()).is_greater(0)

	for k in range(4):
		var stored := lib.get_stored_index(yaw_base, k)
		var verts := _render_vertex_set(mesher, stored)
		assert_int(verts.size()).is_equal(base_verts.size())
		# Every variant vertex = quarter-turn of a base vertex about the cell
		# center (cell-relative coords span [-1, 0]; center = -0.5).
		var basis := VoxelBlockEncoder.rot_index_to_basis(BlockDef.YAW_INDICES[k])
		var expected := {}
		for v: Vector3 in base_verts:
			expected[basis * (v - Vector3(-0.5, -0.5, -0.5)) + Vector3(-0.5, -0.5, -0.5)] = true
		for v: Vector3 in verts:
			assert_bool(expected.has(v)).is_true()


## Distinct vertex positions of the rendered model at `value`, snapped to
## kill float noise (cell-relative to the voxel).
func _render_vertex_set(mesher: VoxelMesherBlocky, value: int) -> Array:
	var buf := VoxelBuffer.new()
	buf.create(8, 8, 8)
	buf.set_voxel(value, 4, 4, 4, VoxelBuffer.CHANNEL_TYPE)
	var mesh: Mesh = mesher.build_mesh(buf, [] as Array[Material], {})
	var seen := {}
	if mesh != null:
		for i in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(i)
			for v: Vector3 in arr[ArrayMesh.ARRAY_VERTEX]:
				var rel := v - Vector3(4, 4, 4)
				seen[Vector3(round(rel.x * 100.0) / 100.0, round(rel.y * 100.0) / 100.0, round(rel.z * 100.0) / 100.0)] = true
	return seen.keys()

func test_base_indices_contain_only_base_defs() -> void:
	var dir := Fixtures.make_block_dir("base_indices")
	var lib := BlockLibrary.new(dir)
	var base_indices := lib.get_base_indices()
	# 3 fixture base definitions (plain, yawwedge, fullwedge)
	assert_int(base_indices.size()).is_equal(3)
	assert_array(base_indices).contains_exactly([1, 2, 3])

	# Base index check
	for idx in base_indices:
		assert_bool(lib.is_base_index(idx)).is_true()

	# Variants and air are not base indices
	assert_bool(lib.is_base_index(0)).is_false()
	for variant_idx in range(4, lib.get_voxel_library().get_models().size()):
		assert_bool(lib.is_base_index(variant_idx)).is_false()
