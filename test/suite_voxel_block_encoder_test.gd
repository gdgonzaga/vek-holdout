extends GdUnitTestSuite

## The orientation table is the contract between rotation UI state and what
## the mesher renders (mesh_ortho_rotation_index). The convention is pinned
## empirically: for every index, a shared asymmetric mesh is rendered at that
## ortho index through the real mesher and the recovered rotation must equal
## the table entry — so an addon update that changes the convention fails
## here instead of silently mis-rotating content.


func test_index_zero_is_identity() -> void:
	assert_bool(VoxelBlockEncoder.rot_index_to_basis(0).is_equal_approx(Basis())).is_true()


## The four yaw states, in quarter-turn order (see BlockDef.YAW_INDICES).
func test_yaw_indices_are_quarter_turns_about_up() -> void:
	for k in range(4):
		var b := VoxelBlockEncoder.rot_index_to_basis(BlockDef.YAW_INDICES[k])
		assert_bool(b.is_equal_approx(Basis(Vector3.UP, float(k) * PI / 2.0))).is_true()


## Yaw cycling: +90 deg steps about +Y walk the quarter-turn set in order.
func test_rotate_around_axis_yaw_cycles_quarter_turns() -> void:
	var curr := 0
	for k in range(1, 5):
		curr = VoxelBlockEncoder.rotate_around_axis(curr, Vector3.UP, PI / 2.0)
		assert_int(curr).is_equal(BlockDef.YAW_INDICES[k % 4])


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


# --- mesher convention pin ----------------------------------------------------

## Asymmetric authored probe vertices (none coplanar-symmetric — every one of
## the 24 orientations maps them to a distinct triple).
const _PROBE_VERTS: Array[Vector3] = [
	Vector3(0.25, 0.5, 0.75),
	Vector3(0.75, 0.25, 0.5),
	Vector3(0.5, 0.75, 0.25),
]
const _CELL_CENTER := Vector3(0.5, 0.5, 0.5)
const _VOXEL := Vector3i(4, 4, 4)


func _probe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in _PROBE_VERTS:
		st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


## Renders `value` alone in a buffer and returns the mesh vertices relative to
## the voxel position (the cell spans [-1, 0]^3 relative to it).
func _rendered_verts(mesher: VoxelMesherBlocky, value: int) -> Array[Vector3]:
	var buf := VoxelBuffer.new()
	buf.create(8, 8, 8)
	buf.set_voxel(value, _VOXEL.x, _VOXEL.y, _VOXEL.z, VoxelBuffer.CHANNEL_TYPE)
	var mesh: Mesh = mesher.build_mesh(buf, [] as Array[Material], {})
	var out: Array[Vector3] = []
	if mesh == null:
		return out
	for i in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(i)
		for v: Vector3 in arr[ArrayMesh.ARRAY_VERTEX]:
			out.append(v - Vector3(_VOXEL))
	return out


## All 24 proper signed axis-permutation bases (candidate cell rotations).
func _candidate_bases() -> Array[Basis]:
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var out: Array[Basis] = []
	for x: Vector3 in axes:
		for y: Vector3 in axes:
			if absf(x.dot(y)) > 0.5:
				continue
			out.append(Basis(x, y, x.cross(y)))
	return out


## For every orientation index: one shared mesh, 24 models differing only in
## mesh_ortho_rotation_index (exactly how BlockLibrary bakes variants) — the
## rotation the mesher applies must equal the encoder's table entry.
func test_ortho_table_matches_mesher_convention() -> void:
	var lib := VoxelBlockyLibrary.new()
	lib.add_model(VoxelBlockyModelEmpty.new())
	var probe := _probe_mesh()
	for ortho in range(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS):
		var model := VoxelBlockyModelMesh.new()
		model.mesh = probe
		model.mesh_ortho_rotation_index = ortho
		lib.add_model(model)
	lib.bake()
	var mesher := VoxelMesherBlocky.new()
	mesher.library = lib

	var candidates := _candidate_bases()
	for ortho in range(VoxelBlockEncoder.MAX_ORTHO_ROTATIONS):
		var verts := _rendered_verts(mesher, ortho + 1)
		assert_int(verts.size()).is_equal(3)
		if verts.size() != 3:
			continue
		# w = R * (authored - center) + center, in cell-relative coords.
		var recovered: Basis = Basis()
		var found := false
		for cand: Basis in candidates:
			var ok := true
			for j: int in [0, 1, 2]:
				var u: Vector3 = _PROBE_VERTS[j] - _CELL_CENTER
				var w: Vector3 = verts[j] + Vector3.ONE - _CELL_CENTER
				if not (cand * u).is_equal_approx(w):
					ok = false
					break
			if ok:
				recovered = cand
				found = true
				break
		assert_bool(found).is_true()
		if found:
			assert_bool(recovered.is_equal_approx(VoxelBlockEncoder.rot_index_to_basis(ortho))).is_true()
