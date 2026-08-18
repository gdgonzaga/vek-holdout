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
		
	# Non-yaw orthogonal indices should map to nearest horizontal yaw state
	assert_int(def.sanitize_rotation(0)).is_equal(3)
	assert_int(def.sanitize_rotation(4)).is_equal(7)
	assert_int(def.sanitize_rotation(8)).is_equal(19)
	assert_int(def.sanitize_rotation(10)).is_equal(23)


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
	def.base_library_id = 3
	def.rotation_mode = BlockDef.RotationMode.YAW_ONLY
	
	VoxelLibraryGenerator.register_block_in_library(def, lib)
	var models: Array = lib.get_models()
	assert_int(models.size()).is_equal(7)
	assert_str(models[3].resource_name).is_equal("ramp_%d" % BlockDef.YAW_INDICES[0])
