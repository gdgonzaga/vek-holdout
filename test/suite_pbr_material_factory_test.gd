extends GdUnitTestSuite
## PbrMaterialFactory: how a PbrTextureSet becomes a render material for blocks
## and furniture. In-memory textures only, including the neutral fill (passed in),
## so no shipped asset is read.


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))


func _make_set(albedo: Texture2D, normal: Texture2D, orme: Texture2D) -> PbrTextureSet:
	var texture_set: PbrTextureSet = auto_free(PbrTextureSet.new())
	texture_set.albedo = albedo
	texture_set.normal = normal
	texture_set.orme = orme
	return texture_set


func test_standard_binds_albedo_normal_and_the_orme_channels() -> void:
	var texture_set := _make_set(_texture(), _texture(), _texture())
	var material := PbrMaterialFactory.standard(texture_set)
	assert_object(material.albedo_texture).is_same(texture_set.albedo)
	assert_bool(material.normal_enabled).is_true()
	assert_object(material.normal_texture).is_same(texture_set.normal)
	assert_bool(material.ao_enabled).is_true()
	assert_object(material.ao_texture).is_same(texture_set.orme)
	assert_int(material.ao_texture_channel).is_equal(BaseMaterial3D.TEXTURE_CHANNEL_RED)
	assert_object(material.roughness_texture).is_same(texture_set.orme)
	assert_int(material.roughness_texture_channel).is_equal(BaseMaterial3D.TEXTURE_CHANNEL_GREEN)
	assert_float(material.metallic).is_equal(1.0)
	assert_object(material.metallic_texture).is_same(texture_set.orme)
	assert_int(material.metallic_texture_channel).is_equal(BaseMaterial3D.TEXTURE_CHANNEL_BLUE)


func test_standard_albedo_only_leaves_normal_and_pbr_channels_off() -> void:
	var material := PbrMaterialFactory.standard(_make_set(_texture(), null, null))
	assert_bool(material.normal_enabled).is_false()
	assert_bool(material.ao_enabled).is_false()
	assert_float(material.metallic).is_equal(0.0)


func test_standard_from_a_null_set_is_a_plain_material() -> void:
	var material := PbrMaterialFactory.standard(null)
	assert_object(material).is_not_null()
	assert_object(material.albedo_texture).is_null()


func test_variation_binds_the_sets_maps() -> void:
	var texture_set := _make_set(_texture(), _texture(), _texture())
	var material := PbrMaterialFactory.variation(texture_set)
	assert_object(material.get_shader_parameter("albedo_tex")).is_same(texture_set.albedo)
	assert_object(material.get_shader_parameter("normal_tex")).is_same(texture_set.normal)
	assert_object(material.get_shader_parameter("orme_tex")).is_same(texture_set.orme)


func test_variation_fills_missing_maps_from_the_given_neutral_set() -> void:
	var neutral := _make_set(_texture(), _texture(), _texture())
	var material := PbrMaterialFactory.variation(_make_set(_texture(), null, null), neutral)
	assert_object(material.get_shader_parameter("normal_tex")).is_same(neutral.normal)
	assert_object(material.get_shader_parameter("orme_tex")).is_same(neutral.orme)
