extends GdUnitTestSuite
## PbrTextureSet: the null-safe presence helpers and the neutral-value contract
## the packer and the terrain arrays both rely on. neutral() itself needs the
## generated neutral.tres and is checked against the real import in Task 3 step 8.


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))


func test_has_any_is_false_for_null_and_empty_sets() -> void:
	assert_bool(PbrTextureSet.has_any(null)).is_false()
	assert_bool(PbrTextureSet.has_any(auto_free(PbrTextureSet.new()))).is_false()


func test_has_any_is_true_when_any_single_map_is_set() -> void:
	var only_orme: PbrTextureSet = auto_free(PbrTextureSet.new())
	only_orme.orme = _texture()
	assert_bool(PbrTextureSet.has_any(only_orme)).is_true()


func test_has_albedo_requires_the_albedo_map_specifically() -> void:
	var only_normal: PbrTextureSet = auto_free(PbrTextureSet.new())
	only_normal.normal = _texture()
	assert_bool(PbrTextureSet.has_albedo(only_normal)).is_false()
	assert_bool(PbrTextureSet.has_albedo(null)).is_false()
	only_normal.albedo = _texture()
	assert_bool(PbrTextureSet.has_albedo(only_normal)).is_true()


func test_neutral_values_mean_flat_rough_non_metal_unoccluded() -> void:
	assert_that(PbrTextureSet.NEUTRAL_NORMAL).is_equal(Color8(128, 128, 255, 255))
	assert_that(PbrTextureSet.NEUTRAL_ORME).is_equal(Color(1.0, 1.0, 0.0, 0.0))
