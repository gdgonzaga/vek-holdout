extends GdUnitTestSuite
## PbrPacker: everything the offline packer decides that is not file IO.
## In-memory Images only (no downloaded assets), so the tests pin the packing
## rules (roles, channel order, neutral defaults, DX->GL flip), not any content.

const _AMBIENTCG_FILES: PackedStringArray = [
	"Ground037_1K-PNG_AmbientOcclusion.png", "Ground037_1K-PNG_AmbientOcclusion.png.import",
	"Ground037_1K-PNG_Color.png", "Ground037_1K-PNG_Displacement.png",
	"Ground037_1K-PNG_NormalDX.png", "Ground037_1K-PNG_NormalGL.png",
	"Ground037_1K-PNG_Roughness.png", "Ground037_1K-PNG.tres", "Ground037.png",
]


func _solid(size: int, format: Image.Format, color: Color) -> Image:
	var image := Image.create(size, size, false, format)
	image.fill(color)
	return image


# --- role discovery --------------------------------------------------------------------

func test_discover_roles_maps_ambientcg_names_and_ignores_the_rest() -> void:
	var found := PbrPacker.discover_roles(_AMBIENTCG_FILES)
	assert_str(found[PbrPacker.Role.ALBEDO]).is_equal("Ground037_1K-PNG_Color.png")
	assert_str(found[PbrPacker.Role.NORMAL_GL]).is_equal("Ground037_1K-PNG_NormalGL.png")
	assert_str(found[PbrPacker.Role.NORMAL_DX]).is_equal("Ground037_1K-PNG_NormalDX.png")
	assert_str(found[PbrPacker.Role.ROUGHNESS]).is_equal("Ground037_1K-PNG_Roughness.png")
	assert_str(found[PbrPacker.Role.AMBIENT_OCCLUSION]).is_equal("Ground037_1K-PNG_AmbientOcclusion.png")
	assert_bool(found.has(PbrPacker.Role.METALNESS)).is_false()
	# Displacement, the preview png, the .tres and the .import sidecar are not maps.
	assert_int(found.size()).is_equal(5)


func test_discover_roles_maps_plain_basename_sources() -> void:
	var found := PbrPacker.discover_roles(["basecolor.PNG", "normal.PNG", "roughness.PNG", "orme.PNG", "height.PNG"])
	assert_str(found[PbrPacker.Role.ALBEDO]).is_equal("basecolor.PNG")
	assert_str(found[PbrPacker.Role.NORMAL_GL]).is_equal("normal.PNG")
	assert_str(found[PbrPacker.Role.ORME]).is_equal("orme.PNG")
	assert_bool(found.has(PbrPacker.Role.AMBIENT_OCCLUSION)).is_false()


func test_discover_roles_is_stable_when_two_files_claim_a_role() -> void:
	var forward := PbrPacker.discover_roles(["b_Color.png", "a_Color.png"])
	var reversed := PbrPacker.discover_roles(["a_Color.png", "b_Color.png"])
	assert_str(forward[PbrPacker.Role.ALBEDO]).is_equal("a_Color.png")
	assert_str(reversed[PbrPacker.Role.ALBEDO]).is_equal("a_Color.png")


# --- normal preparation ----------------------------------------------------------------

func test_prepare_normal_without_a_source_is_flat() -> void:
	var normal := PbrPacker.prepare_normal(null, 4, false)
	assert_that(normal.get_pixel(0, 0)).is_equal(Color8(128, 128, 255))
	assert_int(normal.get_width()).is_equal(4)


func test_prepare_normal_flip_inverts_only_green() -> void:
	var source := _solid(2, Image.FORMAT_RGB8, Color8(10, 20, 250))
	var flipped := PbrPacker.prepare_normal(source, 2, true)
	var pixel := flipped.get_pixel(1, 1)
	assert_int(pixel.r8).is_equal(10)
	assert_int(pixel.g8).is_equal(235)
	assert_int(pixel.b8).is_equal(250)


func test_prepare_normal_resizes_to_the_requested_size() -> void:
	var source := _solid(8, Image.FORMAT_RGB8, Color8(128, 128, 255))
	assert_int(PbrPacker.prepare_normal(source, 4, false).get_width()).is_equal(4)


func test_prepare_normal_downscale_restores_unit_length() -> void:
	# Bytes (192, 128, 128) decode to a vector of length about 0.51: too short to be a normal.
	var source := _solid(8, Image.FORMAT_RGB8, Color8(192, 128, 128))
	var pixel := PbrPacker.prepare_normal(source, 4, false).get_pixel(0, 0)
	var x := pixel.r * 2.0 - 1.0
	var y := pixel.g * 2.0 - 1.0
	var z := pixel.b * 2.0 - 1.0
	assert_float(sqrt(x * x + y * y + z * z)).is_between(0.98, 1.02)


func test_valid_sizes_are_multiples_of_four_and_at_least_four() -> void:
	assert_bool(PbrPacker.is_valid_size(4)).is_true()
	assert_bool(PbrPacker.is_valid_size(1024)).is_true()
	assert_bool(PbrPacker.is_valid_size(6)).is_false()
	assert_bool(PbrPacker.is_valid_size(2)).is_false()
	assert_bool(PbrPacker.is_valid_size(0)).is_false()


# --- albedo ---------------------------------------------------------------------------

func test_prepare_albedo_drops_alpha_and_resizes() -> void:
	var source := _solid(8, Image.FORMAT_RGBA8, Color8(200, 100, 50, 10))
	var albedo := PbrPacker.prepare_albedo(source, 4)
	assert_int(albedo.get_format()).is_equal(Image.FORMAT_RGB8)
	assert_int(albedo.get_width()).is_equal(4)
	assert_int(albedo.get_pixel(0, 0).r8).is_equal(200)


# --- ORME packing ----------------------------------------------------------------------

func test_pack_orme_with_no_maps_is_the_neutral_orme() -> void:
	var orme := PbrPacker.pack_orme(null, null, null, 2)
	var pixel := orme.get_pixel(0, 0)
	assert_int(pixel.r8).is_equal(255)
	assert_int(pixel.g8).is_equal(255)
	assert_int(pixel.b8).is_equal(0)
	assert_int(pixel.a8).is_equal(0)


func test_pack_orme_channel_order_is_occlusion_roughness_metalness() -> void:
	var ao := _solid(2, Image.FORMAT_L8, Color8(100, 100, 100))
	var roughness := _solid(2, Image.FORMAT_L8, Color8(150, 150, 150))
	var metalness := _solid(2, Image.FORMAT_L8, Color8(200, 200, 200))
	var pixel := PbrPacker.pack_orme(ao, roughness, metalness, 2).get_pixel(1, 0)
	assert_int(pixel.r8).is_equal(100)
	assert_int(pixel.g8).is_equal(150)
	assert_int(pixel.b8).is_equal(200)
	assert_int(pixel.a8).is_equal(0)


func test_pack_orme_defaults_only_the_missing_channel() -> void:
	var roughness := _solid(2, Image.FORMAT_L8, Color8(90, 90, 90))
	var pixel := PbrPacker.pack_orme(null, roughness, null, 2).get_pixel(0, 0)
	assert_int(pixel.r8).is_equal(255)
	assert_int(pixel.g8).is_equal(90)
	assert_int(pixel.b8).is_equal(0)


func test_prepacked_orme_forces_extra_channel_to_zero() -> void:
	var source := _solid(2, Image.FORMAT_RGBA8, Color8(10, 20, 30, 255))
	var pixel := PbrPacker.prepare_prepacked_orme(source, 2).get_pixel(0, 0)
	assert_int(pixel.r8).is_equal(10)
	assert_int(pixel.b8).is_equal(30)
	assert_int(pixel.a8).is_equal(0)


# --- whole-set packing -----------------------------------------------------------------

func test_pack_set_without_albedo_reports_an_error() -> void:
	assert_bool(PbrPacker.pack_set({}, 4).has("error")).is_true()


func test_pack_set_albedo_only_defaults_normal_and_orme_and_reports_them() -> void:
	var images := {PbrPacker.Role.ALBEDO: _solid(4, Image.FORMAT_RGB8, Color8(1, 2, 3))}
	var packed := PbrPacker.pack_set(images, 4)
	assert_that(packed["normal"].get_pixel(0, 0)).is_equal(Color8(128, 128, 255))
	assert_int(packed["orme"].get_pixel(0, 0).r8).is_equal(255)
	assert_array(packed["missing"]).contains_exactly(["normal", "ambient occlusion", "roughness", "metalness"])


func test_pack_set_prefers_opengl_normals_over_directx() -> void:
	var images := {
		PbrPacker.Role.ALBEDO: _solid(2, Image.FORMAT_RGB8, Color.WHITE),
		PbrPacker.Role.NORMAL_GL: _solid(2, Image.FORMAT_RGB8, Color8(10, 20, 250)),
		PbrPacker.Role.NORMAL_DX: _solid(2, Image.FORMAT_RGB8, Color8(10, 99, 250)),
	}
	assert_int(PbrPacker.pack_set(images, 2)["normal"].get_pixel(0, 0).g8).is_equal(20)


func test_pack_set_flips_a_directx_only_normal() -> void:
	var images := {
		PbrPacker.Role.ALBEDO: _solid(2, Image.FORMAT_RGB8, Color.WHITE),
		PbrPacker.Role.NORMAL_DX: _solid(2, Image.FORMAT_RGB8, Color8(10, 20, 250)),
	}
	assert_int(PbrPacker.pack_set(images, 2)["normal"].get_pixel(0, 0).g8).is_equal(235)


func test_pack_set_force_flip_applies_to_an_opengl_labelled_normal() -> void:
	var images := {
		PbrPacker.Role.ALBEDO: _solid(2, Image.FORMAT_RGB8, Color.WHITE),
		PbrPacker.Role.NORMAL_GL: _solid(2, Image.FORMAT_RGB8, Color8(10, 20, 250)),
	}
	assert_int(PbrPacker.pack_set(images, 2, true)["normal"].get_pixel(0, 0).g8).is_equal(235)


func test_pack_set_prepacked_orme_wins_over_separate_maps() -> void:
	var images := {
		PbrPacker.Role.ALBEDO: _solid(2, Image.FORMAT_RGB8, Color.WHITE),
		PbrPacker.Role.ORME: _solid(2, Image.FORMAT_RGBA8, Color8(11, 22, 33, 44)),
		PbrPacker.Role.ROUGHNESS: _solid(2, Image.FORMAT_L8, Color8(200, 200, 200)),
	}
	var pixel: Color = PbrPacker.pack_set(images, 2)["orme"].get_pixel(0, 0)
	assert_int(pixel.g8).is_equal(22)
	assert_int(pixel.a8).is_equal(0)


func test_neutral_set_is_flat_unoccluded_rough_and_white() -> void:
	var packed := PbrPacker.neutral_set(2)
	assert_that(packed["albedo"].get_pixel(0, 0)).is_equal(Color.WHITE)
	assert_that(packed["normal"].get_pixel(0, 0)).is_equal(Color8(128, 128, 255))
	assert_int(packed["orme"].get_pixel(0, 0).g8).is_equal(255)
	assert_int(packed["orme"].get_pixel(0, 0).b8).is_equal(0)
