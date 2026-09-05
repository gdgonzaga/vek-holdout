extends GdUnitTestSuite

func test_sanitize_rotation_none() -> void:
	var def: BlockDef = auto_free(BlockDef.new())
	def.rotation_mode = BlockDef.RotationMode.NONE
	assert_bool(def.is_rotatable()).is_false()
	assert_int(def.sanitize_rotation(0)).is_equal(0)
	assert_int(def.sanitize_rotation(5)).is_equal(0)
	assert_int(def.sanitize_rotation(-10)).is_equal(0)
	assert_int(def.sanitize_rotation(23)).is_equal(0)


func test_sanitize_rotation_yaw_only() -> void:
	var def: BlockDef = auto_free(BlockDef.new())
	def.rotation_mode = BlockDef.RotationMode.YAW_ONLY
	assert_bool(def.is_rotatable()).is_true()

	# Direct orthogonal yaw indices should pass through unchanged
	for idx in BlockDef.YAW_INDICES:
		assert_int(def.sanitize_rotation(idx)).is_equal(idx)

	# Small ints 0..3 are accepted as quarter-turn counts (0 is identity).
	assert_int(def.sanitize_rotation(0)).is_equal(0)
	assert_int(def.sanitize_rotation(1)).is_equal(BlockDef.YAW_INDICES[1])
	assert_int(def.sanitize_rotation(2)).is_equal(BlockDef.YAW_INDICES[2])
	assert_int(def.sanitize_rotation(3)).is_equal(BlockDef.YAW_INDICES[3])

	# Tilted orthogonal indices snap to the nearest horizontal yaw state
	# (basis dot against the yaw set — 4 is a pitch collapsing to 0 deg,
	# 9 and 23 carry a yaw component of 180/90 deg respectively).
	assert_int(def.sanitize_rotation(4)).is_equal(0)
	assert_int(def.sanitize_rotation(9)).is_equal(BlockDef.YAW_INDICES[2])
	assert_int(def.sanitize_rotation(23)).is_equal(BlockDef.YAW_INDICES[1])


func test_sanitize_rotation_full_3d() -> void:
	var def: BlockDef = auto_free(BlockDef.new())
	def.rotation_mode = BlockDef.RotationMode.FULL_3D
	assert_bool(def.is_rotatable()).is_true()
	
	assert_int(def.sanitize_rotation(-5)).is_equal(0)
	for i in range(24):
		assert_int(def.sanitize_rotation(i)).is_equal(i)
	assert_int(def.sanitize_rotation(30)).is_equal(23)


func test_generate_block_models_count() -> void:
	var def_none: BlockDef = auto_free(BlockDef.new())
	def_none.id = "cube"
	def_none.rotation_mode = BlockDef.RotationMode.NONE
	var models_none := VoxelLibraryGenerator.generate_block_models(def_none)
	assert_int(models_none.size()).is_equal(1)
	assert_str(models_none[0].resource_name).is_equal("cube_0")

	var def_yaw: BlockDef = auto_free(BlockDef.new())
	def_yaw.id = "stairs"
	def_yaw.rotation_mode = BlockDef.RotationMode.YAW_ONLY
	var models_yaw := VoxelLibraryGenerator.generate_block_models(def_yaw)
	assert_int(models_yaw.size()).is_equal(4)
	for i in range(4):
		assert_str(models_yaw[i].resource_name).is_equal("stairs_%d" % BlockDef.YAW_INDICES[i])
		assert_int(models_yaw[i].mesh_ortho_rotation_index).is_equal(BlockDef.YAW_INDICES[i])

	var def_3d: BlockDef = auto_free(BlockDef.new())
	def_3d.id = "wedge"
	def_3d.rotation_mode = BlockDef.RotationMode.FULL_3D
	var models_3d := VoxelLibraryGenerator.generate_block_models(def_3d)
	assert_int(models_3d.size()).is_equal(24)
	for i in range(24):
		assert_str(models_3d[i].resource_name).is_equal("wedge_%d" % i)
		assert_int(models_3d[i].mesh_ortho_rotation_index).is_equal(i)


func test_register_block_in_library() -> void:
	var lib: VoxelBlockyLibrary = auto_free(VoxelBlockyLibrary.new())
	var def: BlockDef = auto_free(BlockDef.new())
	def.id = "ramp"
	def.rotation_mode = BlockDef.RotationMode.YAW_ONLY

	VoxelLibraryGenerator.register_block_in_library(def, lib, 3)
	var models: Array = lib.get_models()
	assert_int(models.size()).is_equal(7)
	assert_str(models[3].resource_name).is_equal("ramp_%d" % BlockDef.YAW_INDICES[0])


func test_buildable_def_get_mesh_prefers_explicit_mesh() -> void:
	var def: BuildableDef = auto_free(BuildableDef.new())
	var explicit_mesh := BoxMesh.new()
	def.mesh = explicit_mesh
	assert_object(def.get_mesh()).is_equal(explicit_mesh)


func test_buildable_def_get_mesh_extracts_from_scene() -> void:
	var def: BuildableDef = auto_free(BuildableDef.new())
	var packed_scene := PackedScene.new()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	mi.mesh = cylinder
	root.add_child(mi)
	mi.owner = root
	packed_scene.pack(root)
	root.free()

	def.scene = packed_scene
	var extracted: Mesh = def.get_mesh()
	assert_object(extracted).is_equal(cylinder)


func test_block_def_with_scene_generates_block_models() -> void:
	var def: BlockDef = auto_free(BlockDef.new())
	def.id = "scene_block"
	def.rotation_mode = BlockDef.RotationMode.YAW_ONLY

	var packed_scene := PackedScene.new()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	mi.mesh = box
	root.add_child(mi)
	mi.owner = root
	packed_scene.pack(root)
	root.free()

	def.scene = packed_scene

	var models := VoxelLibraryGenerator.generate_block_models(def)
	assert_int(models.size()).is_equal(4)
	assert_object(models[0].mesh).is_equal(box)
