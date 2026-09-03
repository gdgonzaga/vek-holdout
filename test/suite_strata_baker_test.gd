extends GdUnitTestSuite
## Test suite for StrataBaker (Option B2 volumetric 3D texture generator).
## Verifies palette construction, 3D volume dimensions, threaded execution,
## and 100% spatial identity matching against TerrainStrata.

const StrataBaker = preload("res://subsystems/voxel/strata_baker.gd")
const StrataBakeResult = preload("res://subsystems/voxel/strata_bake_result.gd")


func _make_def(id: String, min_depth: int, max_depth: int, weight: float, vein_sz: int = 8) -> TerrainMaterialDef:
	var def: TerrainMaterialDef = auto_free(TerrainMaterialDef.new())
	def.id = id
	def.display_name = id
	def.min_depth = min_depth
	def.max_depth = max_depth
	def.spawn_weight = weight
	def.vein_size = vein_sz
	return def


func test_build_palette_assigns_zero_to_background_and_sequential_to_ores() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var coal := _make_def("coal", 4, 100, 0.5)
	var copper := _make_def("copper", 8, 100, 0.5)
	var iron := _make_def("iron", 12, 100, 0.5)

	var palette: Dictionary = StrataBaker.build_palette([ground, rock, coal, copper, iron])
	assert_int(palette["ground"]).is_equal(0)
	assert_int(palette["rock"]).is_equal(0)
	assert_int(palette["coal"]).is_equal(1)
	assert_int(palette["copper"]).is_equal(2)
	assert_int(palette["iron"]).is_equal(3)


func test_build_palette_deterministic_across_array_order() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var a_ore := _make_def("a_ore", 4, 100, 0.5)
	var z_ore := _make_def("z_ore", 4, 100, 0.5)

	var p1: Dictionary = StrataBaker.build_palette([z_ore, rock, a_ore, ground])
	var p2: Dictionary = StrataBaker.build_palette([ground, a_ore, rock, z_ore])

	assert_dict(p1).is_equal(p2)
	assert_int(p1["a_ore"]).is_equal(1)
	assert_int(p1["z_ore"]).is_equal(2)


func test_bake_rejects_invalid_inputs_cleanly() -> void:
	var strata: TerrainStrata = auto_free(TerrainStrata.new())
	var palette := {"ground": 0, "ore": 1}

	assert_object(StrataBaker.bake(null, palette, Vector3i.ZERO, Vector3i(16, 16, 16))).is_null()
	assert_object(StrataBaker.bake(strata, palette, Vector3i.ZERO, Vector3i(0, 16, 16))).is_null()
	assert_object(StrataBaker.bake(strata, palette, Vector3i.ZERO, Vector3i(16, -5, 16))).is_null()


func test_bake_creates_valid_texture_and_dimensions() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var ore := _make_def("test_ore", 4, 100, 0.5)

	var strata: TerrainStrata = auto_free(TerrainStrata.new())
	strata.setup([ground, rock, ore], 1234, func(_x: float, _z: float) -> float: return 10.0)

	var palette: Dictionary = StrataBaker.build_palette([ground, rock, ore])
	var origin := Vector3i(-8, -4, -8)
	var size := Vector3i(16, 8, 16)

	var result: StrataBakeResult = StrataBaker.bake(strata, palette, origin, size, Callable(), false, true)
	assert_object(result).is_not_null()
	assert_object(result.texture).is_not_null()
	assert_int(result.texture.get_width()).is_equal(16)
	assert_int(result.texture.get_height()).is_equal(8)
	assert_int(result.texture.get_depth()).is_equal(16)
	assert_int(result.slices.size()).is_equal(16)


func test_bake_matches_terrain_strata_spatial_samples_exactly() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var ore := _make_def("rare_ore", 5, 20, 0.8, 4)

	var strata: TerrainStrata = auto_free(TerrainStrata.new())
	strata.setup([ground, rock, ore], 4321, func(x: float, z: float) -> float:
		return 15.0 + sin(x * 0.1) * 2.0 + cos(z * 0.1) * 2.0
	)

	var palette: Dictionary = StrataBaker.build_palette([ground, rock, ore])
	var origin := Vector3i(10, 0, 10)
	var size := Vector3i(12, 12, 12)

	var result: StrataBakeResult = StrataBaker.bake(strata, palette, origin, size, Callable(), true, true)
	assert_object(result).is_not_null()

	# Sample multiple voxels across the volume and assert 100% lockstep match
	for sz: int in [0, 5, 11]:
		for sy: int in [0, 6, 11]:
			for sx: int in [0, 4, 11]:
				var pos := origin + Vector3i(sx, sy, sz)
				var expected_id: String = strata.material_id_at(pos)
				var baked_id: String = result.sample_material_id(pos)

				if expected_id in ["ground", "rock"]:
					# Background materials map to palette index 0
					assert_str(baked_id).is_equal("")
					assert_int(result.sample_palette_index(pos)).is_equal(0)
				else:
					assert_str(baked_id).is_equal(expected_id)
					assert_int(result.sample_palette_index(pos)).is_equal(palette[expected_id])


func test_bake_threaded_matches_single_threaded_output() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var ore_a := _make_def("ore_a", 4, 30, 0.5)
	var ore_b := _make_def("ore_b", 10, 50, 0.5)

	var strata: TerrainStrata = auto_free(TerrainStrata.new())
	strata.setup([ground, rock, ore_a, ore_b], 9876, func(_x: float, _z: float) -> float: return 12.0)

	var palette: Dictionary = StrataBaker.build_palette([ground, rock, ore_a, ore_b])
	var origin := Vector3i(-10, -5, -10)
	var size := Vector3i(16, 10, 16)

	var seq_res: StrataBakeResult = StrataBaker.bake(strata, palette, origin, size, Callable(), false, true)
	var thr_res: StrataBakeResult = StrataBaker.bake(strata, palette, origin, size, Callable(), true, true)

	assert_object(seq_res).is_not_null()
	assert_object(thr_res).is_not_null()

	# Verify every single slice and byte is byte-identical
	for z in size.z:
		var seq_data: PackedByteArray = seq_res.slices[z].get_data()
		var thr_data: PackedByteArray = thr_res.slices[z].get_data()
		assert_bool(seq_data == thr_data).is_true()
