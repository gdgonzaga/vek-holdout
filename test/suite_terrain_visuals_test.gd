extends GdUnitTestSuite
## Smooth-terrain visuals (F11/F14): the pure halves of the system — band
## endpoint selection (which catalog materials the depth-band shader blends),
## tint/texture fallback rules, and the marker helpers (bounding sphere,
## radial disc). The runtime halves (material_override wiring, the pristine
## height bake, Decal spawning) are voxel_tool-bound and stay covered by the
## F14 spike + manual playtest instead (docs/architecture/mining.md).


func _make_def(id: String, min_depth: int, max_depth: int, weight: float) -> TerrainMaterialDef:
	var def: TerrainMaterialDef = auto_free(TerrainMaterialDef.new())
	def.id = id
	def.display_name = id
	def.min_depth = min_depth
	def.max_depth = max_depth
	def.spawn_weight = weight
	return def


# --- band endpoint selection -------------------------------------------------------

func test_band_picks_prefer_surface_min_depth_and_dominant_deep() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 10.0)
	var iron := _make_def("iron_ore", 12, 0x7FFFFFFF, 2.0)
	var gold := _make_def("gold_ore", 24, 0x7FFFFFFF, 1.0)
	var picks := SmoothGrid._pick_band_materials([ground, rock, iron, gold])
	assert_str(picks["surface"].id).is_equal("ground")
	assert_str(picks["deep"].id).is_equal("rock")


func test_band_picks_survive_catalog_order() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 10.0)
	var iron := _make_def("iron_ore", 12, 0x7FFFFFFF, 2.0)
	var gold := _make_def("gold_ore", 24, 0x7FFFFFFF, 1.0)
	var forward := SmoothGrid._pick_band_materials([ground, rock, iron, gold])
	var shuffled := SmoothGrid._pick_band_materials([gold, iron, ground, rock])
	assert_str(shuffled["surface"].id).is_equal(forward["surface"].id)
	assert_str(shuffled["deep"].id).is_equal(forward["deep"].id)


func test_band_picks_exclude_shallow_contenders_from_deep() -> void:
	# clay starts ABOVE the surface material's max_depth, so however common it
	# is, it cannot be the deep band.
	var ground := _make_def("ground", 0, 3, 1.0)
	var clay := _make_def("clay", 1, 2, 99.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 10.0)
	var picks := SmoothGrid._pick_band_materials([ground, clay, rock])
	assert_str(picks["deep"].id).is_equal("rock")


func test_band_picks_prefer_surface_highest_spawn_weight_on_min_depth_tie() -> void:
	var rare := _make_def("a_rare_ore", 0, 10, 0.1)
	var dominant := _make_def("z_ground", 0, 3, 1.0)
	var picks := SmoothGrid._pick_band_materials([rare, dominant])
	assert_str(picks["surface"].id).is_equal("z_ground")


func test_band_picks_break_ties_on_id() -> void:
	var b := _make_def("b_surface", 0, 2, 1.0)
	var a := _make_def("a_surface", 0, 2, 1.0)
	var picks := SmoothGrid._pick_band_materials([b, a])
	assert_str(picks["surface"].id).is_equal("a_surface")


func test_band_picks_selects_ore_preferring_texture() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 10.0)
	var common_ore := _make_def("common_ore", 5, 0x7FFFFFFF, 5.0)
	var textured_ore := _make_def("textured_ore", 1, 0x7FFFFFFF, 0.5)
	textured_ore.texture = SmoothGrid.marker_texture()
	var picks := SmoothGrid._pick_band_materials([ground, rock, common_ore, textured_ore])
	assert_str(picks["ore"].id).is_equal("textured_ore")


func test_band_picks_selects_dominant_ore_when_no_texture() -> void:
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 10.0)
	var rare_ore := _make_def("rare_ore", 10, 0x7FFFFFFF, 0.5)
	var dominant_ore := _make_def("dominant_ore", 5, 0x7FFFFFFF, 2.0)
	var picks := SmoothGrid._pick_band_materials([ground, rock, rare_ore, dominant_ore])
	assert_str(picks["ore"].id).is_equal("dominant_ore")


func test_band_picks_deep_prefers_lowest_min_depth_over_spawn_weight() -> void:
	## Deep band must pick rock (min_depth=3) over copper (min_depth=8) even
	## when both have spawn_weight=1.0 and copper would win alphabetically.
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var copper := _make_def("copper", 8, 0x7FFFFFFF, 1.0)
	var picks := SmoothGrid._pick_band_materials([ground, rock, copper])
	assert_str(picks["deep"].id).is_equal("rock")


func test_band_picks_ore_is_coal_with_real_catalog_shape() -> void:
	## End-to-end: with the actual catalog shape (ground/rock/coal/copper),
	## surface=ground, deep=rock, ore=coal (only textured non-endpoint).
	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var coal := _make_def("coal", 0, 100, 0.9)
	coal.texture = SmoothGrid.marker_texture()
	var copper := _make_def("copper", 8, 0x7FFFFFFF, 1.0)
	var picks := SmoothGrid._pick_band_materials([ground, rock, coal, copper])
	assert_str(picks["surface"].id).is_equal("ground")
	assert_str(picks["deep"].id).is_equal("rock")
	assert_str(picks["ore"].id).is_equal("coal")


func test_band_picks_empty_catalog_answers_nothing() -> void:
	assert_dict(SmoothGrid._pick_band_materials([])).is_empty()


# --- band tint / texture fallback --------------------------------------------------

func test_band_tint_uses_def_color_without_texture() -> void:
	var clay := _make_def("clay", 0, 2, 1.0)
	clay.color = Color(0.5, 0.2, 0.1, 1.0)
	assert_that(SmoothGrid._band_tint(clay, Color.BLACK)).is_equal(Color(0.5, 0.2, 0.1, 1.0))


func test_band_tint_falls_back_to_shader_default_for_white_defs() -> void:
	var plain := _make_def("plain", 0, 2, 1.0)
	assert_that(SmoothGrid._band_tint(plain, Color.BLACK)).is_equal(Color.BLACK)


func test_band_tint_never_tints_a_real_texture() -> void:
	var textured := _make_def("textured", 0, 2, 1.0)
	textured.texture = SmoothGrid.marker_texture()
	assert_that(SmoothGrid._band_tint(textured, Color.BLACK)).is_equal(Color.WHITE)


# --- marker helpers ------------------------------------------------------------------

func test_marker_sphere_clamps_single_positions_to_minimum() -> void:
	var sphere := SmoothGrid.marker_sphere_for([Vector3i(5, -3, 2)])
	assert_vector(sphere["center"]).is_equal(Vector3(5, -3, 2))
	assert_float(sphere["radius"]).is_equal(1.5)


func test_marker_sphere_clamps_giant_blobs_and_centers() -> void:
	var positions: Array = []
	for i: int in 40:
		positions.append(Vector3i(i * 10, 0, 0))
	var sphere := SmoothGrid.marker_sphere_for(positions)
	assert_float(sphere["radius"]).is_equal(6.0)
	assert_float(sphere["center"].x).is_equal(195.0)


func test_marker_texture_fades_from_center_to_edge() -> void:
	var image: Image = SmoothGrid.marker_texture().get_image()
	var center: float = image.get_pixel(32, 32).a
	var mid: float = image.get_pixel(48, 32).a
	var corner: float = image.get_pixel(0, 0).a
	assert_float(center).is_greater(mid)
	assert_float(mid).is_greater(corner)
	assert_float(corner).is_equal(0.0)


func test_smooth_grid_volume_wiring_pushes_shader_uniforms() -> void:
	var grid: SmoothGrid = auto_free(SmoothGrid.new())
	grid.volume_bake_span_xz = 16
	grid.volume_bake_span_y = 8
	grid.volume_min_y = -4

	var gen := TerrainGenDef.new()
	gen.noise_seed = 777
	grid.terrain_gen = gen

	var ground := _make_def("ground", 0, 3, 1.0)
	var rock := _make_def("rock", 3, 0x7FFFFFFF, 1.0)
	var coal := _make_def("coal", 4, 100, 0.9)
	coal.texture = SmoothGrid.marker_texture()

	grid.set_material_catalog([ground, rock, coal])
	grid._bake_strata_volume()

	var result := grid.get_strata_bake_result()
	assert_object(result).is_not_null()
	assert_object(result.texture).is_not_null()

	var mat := ShaderMaterial.new()
	mat.shader = SmoothGrid.TERRAIN_SHADER
	grid._push_band_uniforms(mat)

	assert_bool(mat.get_shader_parameter("volume_enabled")).is_true()
	assert_object(mat.get_shader_parameter("strata_volume")).is_equal(result.texture)
	assert_vector(mat.get_shader_parameter("volume_origin")).is_equal(Vector3(-8, -4, -8))
	assert_vector(mat.get_shader_parameter("volume_size")).is_equal(Vector3(16, 8, 16))
	var textures: Array = mat.get_shader_parameter("ore_textures")
	assert_object(textures[grid.get_strata_palette()["coal"]]).is_equal(coal.texture)
	var tints: Array = mat.get_shader_parameter("ore_palette_tint")
	assert_vector(tints[grid.get_strata_palette()["coal"]]).is_equal(Vector3.ONE)
