extends GdUnitTestSuite
## TerrainTextureArrays: how the catalog's PbrTextureSets become the three
## Texture2DArrays the terrain shader indexes by layer. Hermetic: every test
## injects an in-memory neutral set, so nothing depends on imported assets or
## on game content.

const Role = TerrainTextureArrays.Role


func _texture(size: int, color: Color) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _neutral(size: int) -> PbrTextureSet:
	var texture_set: PbrTextureSet = auto_free(PbrTextureSet.new())
	texture_set.id = "test_neutral"
	texture_set.albedo = _texture(size, Color.WHITE)
	texture_set.normal = _texture(size, Color(0.5, 0.5, 1.0))
	texture_set.orme = _texture(size, Color(1.0, 1.0, 0.0, 0.0))
	return texture_set


func _def(id: String) -> TerrainMaterialDef:
	var def: TerrainMaterialDef = auto_free(TerrainMaterialDef.new())
	def.id = id
	return def


func _def_with_albedo(id: String, texture: Texture2D) -> TerrainMaterialDef:
	var def := _def(id)
	def.pbr = auto_free(PbrTextureSet.new())
	def.pbr.albedo = texture
	return def


func _reference_image(size: int) -> Image:
	return TerrainTextureArrays.texture_image(_neutral(size).albedo)


# --- layer table -----------------------------------------------------------------------

func test_layer_for_palette_index_skips_the_two_band_layers() -> void:
	assert_int(TerrainTextureArrays.layer_for_palette_index(1)).is_equal(2)
	assert_int(TerrainTextureArrays.layer_for_palette_index(15)).is_equal(16)


func test_layer_defs_places_bands_first_then_ores_by_palette_index() -> void:
	var ground := _def("g")
	var rock := _def("r")
	var coal := _def("c")
	var defs := TerrainTextureArrays.layer_defs(ground, rock, {3: coal})
	assert_int(defs.size()).is_equal(5)
	assert_object(defs[TerrainTextureArrays.LAYER_SURFACE]).is_same(ground)
	assert_object(defs[TerrainTextureArrays.LAYER_DEEP]).is_same(rock)
	assert_object(defs[TerrainTextureArrays.layer_for_palette_index(3)]).is_same(coal)
	assert_object(defs[2]).is_null()


func test_layer_defs_with_no_ores_has_only_the_band_layers() -> void:
	assert_int(TerrainTextureArrays.layer_defs(_def("g"), _def("r"), {}).size()).is_equal(2)


func test_layer_defs_ignores_palette_indices_outside_the_ore_range() -> void:
	var defs := TerrainTextureArrays.layer_defs(_def("g"), _def("r"), {0: _def("a"), 16: _def("b")})
	assert_int(defs.size()).is_equal(2)


# --- per-layer image choice --------------------------------------------------------------

func test_layer_image_uses_the_defs_own_map_when_the_layout_matches() -> void:
	var def := _def_with_albedo("a", _texture(4, Color8(51, 102, 153)))
	var problems := PackedStringArray()
	var image := TerrainTextureArrays.layer_image(def, Role.ALBEDO, _reference_image(4), problems)
	assert_int(image.get_pixel(0, 0).r8).is_equal(51)
	assert_array(problems).is_empty()


func test_layer_image_falls_back_to_the_neutral_map_when_the_def_has_no_such_map() -> void:
	var def := _def_with_albedo("a", _texture(4, Color8(51, 102, 153)))
	var reference := _reference_image(4)
	var problems := PackedStringArray()
	# The def has an albedo but no normal map: the neutral normal is not a problem, just the default.
	var image := TerrainTextureArrays.layer_image(def, Role.NORMAL, reference, problems)
	assert_object(image).is_same(reference)
	assert_array(problems).is_empty()


func test_layer_image_rejects_a_wrong_sized_map_and_says_so() -> void:
	var def := _def_with_albedo("wrong_size", _texture(8, Color.RED))
	var reference := _reference_image(4)
	var problems := PackedStringArray()
	var image := TerrainTextureArrays.layer_image(def, Role.ALBEDO, reference, problems)
	assert_object(image).is_same(reference)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("wrong_size")


func test_layer_image_for_an_unused_layer_is_the_neutral_map() -> void:
	var reference := _reference_image(4)
	assert_object(TerrainTextureArrays.layer_image(null, Role.ORME, reference, PackedStringArray())).is_same(reference)


# --- scalars ----------------------------------------------------------------------------

func test_layer_tiles_come_from_each_defs_tiles_per_meter() -> void:
	var ground := _def("g")
	ground.tiles_per_meter = 0.5
	var tiles := TerrainTextureArrays.layer_tiles(TerrainTextureArrays.layer_defs(ground, null, {}))
	assert_int(tiles.size()).is_equal(TerrainTextureArrays.MAX_LAYERS)
	assert_float(tiles[TerrainTextureArrays.LAYER_SURFACE]).is_equal(0.5)
	assert_float(tiles[TerrainTextureArrays.LAYER_DEEP]).is_equal(TerrainTextureArrays.DEFAULT_TILES_PER_METER)


func test_tint_for_a_textured_def_is_white() -> void:
	var def := _def_with_albedo("a", _texture(4, Color.RED))
	def.color = Color(0.5, 0.2, 0.1)
	assert_that(TerrainTextureArrays.tint_for(def, Color.BLACK)).is_equal(Color.WHITE)


func test_tint_for_a_textureless_def_uses_its_color() -> void:
	var def := _def("a")
	def.color = Color(0.5, 0.2, 0.1, 1.0)
	assert_that(TerrainTextureArrays.tint_for(def, Color.BLACK)).is_equal(Color(0.5, 0.2, 0.1, 1.0))


func test_tint_for_a_plain_white_textureless_def_uses_the_fallback() -> void:
	assert_that(TerrainTextureArrays.tint_for(_def("a"), Color.BLACK)).is_equal(Color.BLACK)
	assert_that(TerrainTextureArrays.tint_for(null, Color.BLACK)).is_equal(Color.BLACK)


func test_layer_tints_are_max_layers_long_with_band_fallbacks_first() -> void:
	var tints := TerrainTextureArrays.layer_tints(TerrainTextureArrays.layer_defs(null, null, {}))
	assert_int(tints.size()).is_equal(TerrainTextureArrays.MAX_LAYERS)
	assert_vector(tints[TerrainTextureArrays.LAYER_SURFACE]).is_equal(
			Vector3(TerrainTextureArrays.SURFACE_FALLBACK_TINT.r, TerrainTextureArrays.SURFACE_FALLBACK_TINT.g,
			TerrainTextureArrays.SURFACE_FALLBACK_TINT.b))


# --- build ------------------------------------------------------------------------------

func test_build_makes_one_array_layer_per_layer_def() -> void:
	var result := TerrainTextureArrays.build(_def("g"), _def("r"), {2: _def("c")}, _neutral(4))
	assert_int(result.layer_count).is_equal(4)
	assert_int(result.albedo.get_layers()).is_equal(4)
	assert_int(result.normal.get_layers()).is_equal(4)
	assert_int(result.orme.get_layers()).is_equal(4)
	assert_array(result.problems).is_empty()


func test_build_with_no_ores_still_has_the_two_band_layers() -> void:
	var result := TerrainTextureArrays.build(_def("g"), _def("r"), {}, _neutral(4))
	assert_int(result.albedo.get_layers()).is_equal(2)
	assert_int(result.tiles.size()).is_equal(TerrainTextureArrays.MAX_LAYERS)
	assert_int(result.tints.size()).is_equal(TerrainTextureArrays.MAX_LAYERS)
