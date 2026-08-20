## Shared fixtures for the rotation-variant suites: a closed wedge mesh and a
## user:// dir of BlockDef .tres files (one per rotation mode) that
## BlockLibrary scans via its overridable blocks dir — fixture content never
## touches data/blocks/, whose order is save-format-stable.
## Plain script on purpose (never extends GdUnitTestSuite — the runner would
## scan it as a suite).


## Closed unit-cell right-triangle prism (wedge): full base at y=0, vertical
## back wall at z=0, slope down toward +Z. Indexed + normals — the blocky
## mesher requires both on model meshes.
static func wedge_mesh() -> ArrayMesh:
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(1, 0, 1)
	var d := Vector3(0, 0, 1)
	var e := Vector3(0, 1, 0)
	var f := Vector3(1, 1, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri: Array in [
		[a, c, b], [a, d, c],  # bottom
		[a, b, f], [a, f, e],  # back wall (z=0)
		[e, f, c], [e, c, d],  # slope
		[a, d, e],             # side x=0
		[b, c, f],             # side x=1
	]:
		for v: Vector3 in tri:
			st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


## Writes a_plain (NONE), b_yaw (YAW_ONLY), c_full (FULL_3D) and returns the
## dir path. Base indices in a BlockLibrary over this dir: air=0, plain=1,
## yaw=2, full=3 (alphabetical, no terrain fixture).
static func make_block_dir(tag: String) -> String:
	var dir := "user://fixture_blocks_%s/" % tag
	DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(dir)
	if d != null:
		for existing in d.get_files():
			d.remove(existing)
	_write_def(dir + "a_plain.tres", "plain", BlockDef.RotationMode.NONE)
	_write_def(dir + "b_yaw.tres", "yawwedge", BlockDef.RotationMode.YAW_ONLY)
	_write_def(dir + "c_full.tres", "fullwedge", BlockDef.RotationMode.FULL_3D)
	return dir


static func _write_def(path: String, block_id: String, mode: int) -> void:
	var def := BlockDef.new()
	def.id = block_id
	def.display_name = block_id
	def.mesh = wedge_mesh()
	def.rotation_mode = mode
	var err := ResourceSaver.save(def, path)
	assert(err == OK, "fixture save failed at %s (err %d)" % [path, err])
