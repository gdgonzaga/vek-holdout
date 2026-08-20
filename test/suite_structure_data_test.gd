extends GdUnitTestSuite

func test_vox_palette_entry_defaults_and_properties() -> void:
	var entry: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	assert_int(entry.source_index).is_equal(-1)
	assert_str(entry.source_hex).is_equal("")
	assert_int(entry.target_type).is_equal(VoxPaletteEntry.TargetType.BLOCK)
	assert_str(entry.block_id).is_equal("")
	assert_str(entry.terrain_material_id).is_equal("")

	entry.source_index = 1
	entry.source_hex = "#FF5500"
	entry.target_type = VoxPaletteEntry.TargetType.SMOOTH_TERRAIN
	entry.terrain_material_id = "rock"

	assert_int(entry.source_index).is_equal(1)
	assert_str(entry.source_hex).is_equal("#FF5500")
	assert_int(entry.target_type).is_equal(VoxPaletteEntry.TargetType.SMOOTH_TERRAIN)
	assert_str(entry.terrain_material_id).is_equal("rock")


func test_vox_palette_mapping_lookup_by_index() -> void:
	var mapping: VoxPaletteMapping = auto_free(VoxPaletteMapping.new())
	mapping.id = "test_mapping"
	mapping.display_name = "Test Mapping"

	var entry_block: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	entry_block.source_index = 1
	entry_block.source_hex = "FFFFFF"
	entry_block.target_type = VoxPaletteEntry.TargetType.BLOCK
	entry_block.block_id = "stone_wall"

	var entry_air: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	entry_air.source_index = 2
	entry_air.source_hex = "000000"
	entry_air.target_type = VoxPaletteEntry.TargetType.AIR

	mapping.entries.append(entry_block)
	mapping.entries.append(entry_air)

	var found_1: VoxPaletteEntry = mapping.get_target_for_index(1)
	assert_object(found_1).is_not_null()
	assert_int(found_1.target_type).is_equal(VoxPaletteEntry.TargetType.BLOCK)
	assert_str(found_1.block_id).is_equal("stone_wall")

	var found_2: VoxPaletteEntry = mapping.get_target_for_index(2)
	assert_object(found_2).is_not_null()
	assert_int(found_2.target_type).is_equal(VoxPaletteEntry.TargetType.AIR)

	var found_none: VoxPaletteEntry = mapping.get_target_for_index(99)
	assert_object(found_none).is_null()


func test_vox_palette_mapping_lookup_by_hex() -> void:
	var mapping: VoxPaletteMapping = auto_free(VoxPaletteMapping.new())

	var entry: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	entry.source_index = -1
	entry.source_hex = "#AABBCC"
	entry.target_type = VoxPaletteEntry.TargetType.BLOCK
	entry.block_id = "wood_wall"
	mapping.entries.append(entry)

	# Case-insensitive and hash prefix variations
	var found_exact: VoxPaletteEntry = mapping.get_target_for_index(-1, "#aabbcc")
	assert_object(found_exact).is_not_null()
	assert_str(found_exact.block_id).is_equal("wood_wall")

	var found_no_hash: VoxPaletteEntry = mapping.get_target_for_index(-1, "AABBCC")
	assert_object(found_no_hash).is_not_null()
	assert_str(found_no_hash.block_id).is_equal("wood_wall")

	var found_missing: VoxPaletteEntry = mapping.get_target_for_index(-1, "#112233")
	assert_object(found_missing).is_null()


func test_structure_def_properties_and_anchors() -> void:
	var def: StructureDef = auto_free(StructureDef.new())
	assert_str(def.id).is_equal("")
	assert_str(def.display_name).is_equal("")
	assert_str(def.category).is_equal("General")
	assert_str(def.vox_file_path).is_equal("")
	assert_object(def.palette_mapping).is_null()
	assert_int(def.pivot_anchor).is_equal(StructureDef.PivotAnchor.BOTTOM_CENTER)
	assert_vector(def.custom_pivot_offset).is_equal(Vector3i.ZERO)
	assert_vector(def.bounding_box_size).is_equal(Vector3i.ZERO)

	var mapping: VoxPaletteMapping = auto_free(VoxPaletteMapping.new())
	mapping.id = "ruins_mapping"

	def.id = "ruin_tower"
	def.display_name = "Ruin Tower"
	def.category = "Ruins"
	def.vox_file_path = "res://data/structures/vox/ruin_tower.vox"
	def.palette_mapping = mapping
	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CORNER
	def.custom_pivot_offset = Vector3i(1, 0, 1)
	def.bounding_box_size = Vector3i(10, 20, 10)

	assert_str(def.id).is_equal("ruin_tower")
	assert_str(def.display_name).is_equal("Ruin Tower")
	assert_str(def.category).is_equal("Ruins")
	assert_str(def.vox_file_path).is_equal("res://data/structures/vox/ruin_tower.vox")
	assert_object(def.palette_mapping).is_equal(mapping)
	assert_int(def.pivot_anchor).is_equal(StructureDef.PivotAnchor.BOTTOM_CORNER)
	assert_vector(def.custom_pivot_offset).is_equal(Vector3i(1, 0, 1))
	assert_vector(def.bounding_box_size).is_equal(Vector3i(10, 20, 10))
