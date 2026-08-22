# gdlint:disable=max-line-length
class_name SuiteStructureGhostAndStampingTest
extends GdUnitTestSuite

const Doubles = preload("res://test/helpers/doubles.gd")
const GhostPreviewBuilderClass = preload("res://subsystems/map_authoring/ghost_preview_builder.gd")
const StructureToolClass = preload("res://tools/map_editor/structure_tool.gd")
const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")

class MockVoxelGridAdapter extends VoxelGridAdapter:
	var _blocks: Dictionary = {}
	var _raws: Dictionary = {}

	func get_block_at(pos: Vector3i) -> String:
		return _blocks.get(pos, "")

	func set_block_at(pos: Vector3i, block_id: String, _rot_index: int = 0) -> void:
		_blocks[pos] = block_id
		_raws[pos] = 1 if not block_id.is_empty() else 0

	func remove_block_at(pos: Vector3i) -> void:
		_blocks.erase(pos)
		_raws.erase(pos)

	func get_raw_voxel(pos: Vector3i) -> int:
		return _raws.get(pos, 0)

	func set_raw_voxel(pos: Vector3i, raw_val: int) -> void:
		_raws[pos] = raw_val
		if raw_val > 0:
			_blocks[pos] = "raw_%d" % raw_val
		else:
			_blocks.erase(pos)


func _create_sample_vox_data() -> VoxData:
	var data: VoxData = auto_free(VoxData.new())
	data.dimensions = Vector3i(3, 2, 3)
	data.palette = [
		Color(1.0, 0.0, 0.0, 1.0), # 1: Red
		Color(0.0, 1.0, 0.0, 1.0), # 2: Green
		Color(0.0, 0.0, 1.0, 1.0), # 3: Blue
		Color(1.0, 1.0, 0.0, 1.0), # 4: Yellow
	]
	data.set_voxel(Vector3i(1, 0, 1), 1)
	data.set_voxel(Vector3i(0, 0, 0), 2)
	data.set_voxel(Vector3i(1, 1, 1), 3)
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


func _create_sample_structure(mapping: VoxPaletteMapping = null) -> StructureDef:
	var def: StructureDef = auto_free(StructureDef.new())
	def.id = "test_structure"
	def.display_name = "Test Structure"
	def.palette_mapping = mapping
	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CENTER
	def.custom_pivot_offset = Vector3i.ZERO
	def.bounding_box_size = Vector3i(3, 2, 3)
	return def


func test_ghost_preview_builder_null_and_empty() -> void:
	var empty_mesh := GhostPreviewBuilderClass.build_mesh(null)
	assert_object(empty_mesh).is_not_null()
	assert_int(empty_mesh.get_surface_count()).is_equal(0)

	var empty_vox: VoxData = auto_free(VoxData.new())
	var empty_mesh2 := GhostPreviewBuilderClass.build_mesh(empty_vox)
	assert_int(empty_mesh2.get_surface_count()).is_equal(0)


func test_ghost_preview_builder_single_voxel() -> void:
	var data: VoxData = auto_free(VoxData.new())
	data.dimensions = Vector3i(1, 1, 1)
	data.palette = [Color.RED]
	data.set_voxel(Vector3i(0, 0, 0), 1)

	var mesh := GhostPreviewBuilderClass.build_mesh(data)
	assert_int(mesh.get_surface_count()).is_equal(1)

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 6 faces * 6 vertices per quad = 36 vertices
	assert_int(verts.size()).is_equal(36)

	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_int(colors.size()).is_equal(36)
	assert_float(colors[0].r).is_equal_approx(1.0, 0.01)
	assert_float(colors[0].g).is_equal_approx(0.0, 0.01)
	assert_float(colors[0].b).is_equal_approx(0.0, 0.01)


func test_ghost_preview_builder_face_culling() -> void:
	var data: VoxData = auto_free(VoxData.new())
	data.dimensions = Vector3i(2, 1, 1)
	data.palette = [Color.BLUE]
	data.set_voxel(Vector3i(0, 0, 0), 1)
	data.set_voxel(Vector3i(1, 0, 0), 1)

	var mesh := GhostPreviewBuilderClass.build_mesh(data)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Two isolated voxels would have 2 * 36 = 72 verts (12 faces).
	# With shared face culled, there are 10 visible faces = 60 verts.
	assert_int(verts.size()).is_equal(60)


func test_ghost_preview_builder_palette_mapping_ignore_and_air() -> void:
	var data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()

	# With mapping: yellow voxel (4) is IGNORE -> omitted.
	# blue voxel (3) is AIR -> air color tint.
	var mesh := GhostPreviewBuilderClass.build_mesh(data, mapping)
	assert_int(mesh.get_surface_count()).is_equal(1)

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 3 active voxels (1, 2, 3): (0,0,0) is isolated (6 faces); (1,0,1) and (1,1,1) touch at Y (culled shared face -> 5+5=10 faces).
	# Total 16 faces * 6 = 96 verts.
	assert_int(verts.size()).is_equal(96)


func test_ghost_preview_builder_material() -> void:
	var mat := GhostPreviewBuilderClass.create_ghost_material(0.5)
	assert_object(mat).is_not_null()
	assert_bool(mat.vertex_color_use_as_albedo).is_true()
	assert_int(mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_float(mat.albedo_color.a).is_equal_approx(0.5, 0.01)


func test_structure_tool_ghost_mesh_lifecycle() -> void:
	var tool: StructureToolClass = auto_free(StructureToolClass.new())
	add_child(tool)

	var ghost_inst := tool.get_ghost_mesh_instance()
	assert_object(ghost_inst).is_not_null()
	assert_bool(ghost_inst.visible).is_false()

	var data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var def := _create_sample_structure(mapping)

	tool.set_active_structure(def)
	tool.set_cached_vox_data(data)

	assert_object(ghost_inst.mesh).is_not_null()

	# Activate tool
	tool.activate()
	assert_bool(tool.is_active).is_true()

	# Update position
	tool.update_ghost_position(Vector3i(10, 5, 20))
	assert_bool(tool.is_ghost_visible()).is_true()

	# Pivot for 3x2x3 BOTTOM_CENTER is (1, 0, 1)
	# Origin (10, 5, 20) -> Mesh instance placed at (10, 5, 20) - (1, 0, 1) = (9, 5, 19)
	assert_float(ghost_inst.global_position.x).is_equal_approx(9.0, 0.01)
	assert_float(ghost_inst.global_position.y).is_equal_approx(5.0, 0.01)
	assert_float(ghost_inst.global_position.z).is_equal_approx(19.0, 0.01)

	# Rotate 90 deg clockwise (current_rotation = 1)
	tool.rotate_clockwise()
	assert_int(tool.current_rotation).is_equal(1)
	# Rotated Basis around Y: rot_basis * pivot = Basis(90) * (1, 0, 1) = (1, 0, -1)
	# Mesh pos = (10, 5, 20) - (1, 0, -1) = (9, 5, 21)
	assert_float(ghost_inst.global_position.x).is_equal_approx(9.0, 0.01)
	assert_float(ghost_inst.global_position.y).is_equal_approx(5.0, 0.01)
	assert_float(ghost_inst.global_position.z).is_equal_approx(21.0, 0.01)

	# Deactivate hides ghost
	tool.deactivate()
	assert_bool(tool.is_ghost_visible()).is_false()


func test_structure_tool_stamp_and_bounding_box() -> void:
	var tool: StructureToolClass = auto_free(StructureToolClass.new())
	add_child(tool)

	var data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var def := _create_sample_structure(mapping)

	tool.set_active_structure(def)
	tool.set_cached_vox_data(data)

	var grid: MockVoxelGridAdapter = auto_free(MockVoxelGridAdapter.new())
	var smooth_grid: Doubles.RecordingSmoothGrid = auto_free(Doubles.RecordingSmoothGrid.new())
	grid.set_smooth_grid(smooth_grid)

	var ops := tool.stamp(grid, Vector3i(10, 20, 30))
	assert_int(ops.size()).is_equal(3) # block, terrain, air
	assert_str(grid.get_block_at(Vector3i(10, 20, 30))).is_equal("stone_wall")

	var aabb := tool.calculate_bounding_box(Vector3i(10, 20, 30))
	assert_float(aabb.position.x).is_equal_approx(9.0, 0.01)
	assert_float(aabb.position.y).is_equal_approx(20.0, 0.01)
	assert_float(aabb.position.z).is_equal_approx(29.0, 0.01)


func test_map_editor_structure_stamp_and_undo() -> void:
	var editor: MapEditorClass = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var data := _create_sample_vox_data()
	var mapping := _create_sample_mapping()
	var def := _create_sample_structure(mapping)

	editor._structure_defs = [def]
	editor._selected_structure_idx = 0
	editor._set_mode(MapEditorClass.Mode.STRUCTURE)
	editor._structure_tool.set_cached_vox_data(data)

	var hit := {
		"hit": true,
		"position": Vector3i(10, 20, 30),
		"normal": Vector3i.UP,
		"surface": "blocky",
	}

	# Perform structure stamp
	editor._do_structure_stamp(hit)

	assert_int(editor._undo_stack.size()).is_equal(1)
	assert_str(editor._undo_stack[0]["type"]).is_equal("structure")
	assert_bool(editor._dirty).is_true()

	# Undo stamp
	editor._undo_last()
	assert_int(editor._undo_stack.size()).is_equal(0)

	editor.unload_map()
	await get_tree().process_frame
	await get_tree().process_frame
