class_name PbrPacker
extends RefCounted
## Pure image logic for the offline PBR packer (no file IO; see PbrPackWriter and
## pbr_pack_cli.gd): recognises which downloaded file is which map, then turns a
## folder's worth of maps into the three PbrTextureSet maps at one shared size.
##
## Every output uses a fixed pixel format (albedo RGB8, normal RGB8, ORME RGBA8)
## so that Godot's VRAM compression always picks the same format per map type,
## which Texture2DArray layers require (docs/HOWTO-author-pbr-textures.md).
## Missing source maps are filled with the PbrTextureSet neutral values, so the
## output is always a complete set.

## Map roles a downloaded file can play. NORMAL_GL is OpenGL (Y+, what Godot
## uses); NORMAL_DX is DirectX (Y-), converted by flipping green.
enum Role { ALBEDO, NORMAL_GL, NORMAL_DX, ROUGHNESS, AMBIENT_OCCLUSION, METALNESS, ORME }

## The last "_"-separated token of a lower-cased file name (without extension)
## decides the role: ambientCG names are `<Id>_<Res>-<Fmt>_<Map>.png` and
## Realer Than Real names are the bare map name.
const _ROLE_TOKENS: Dictionary = {
	Role.ALBEDO: ["color", "basecolor", "albedo"],
	Role.NORMAL_GL: ["normalgl", "normal"],
	Role.NORMAL_DX: ["normaldx"],
	Role.ROUGHNESS: ["roughness"],
	Role.AMBIENT_OCCLUSION: ["ambientocclusion", "ao"],
	Role.METALNESS: ["metalness", "metallic"],
	Role.ORME: ["orme"],
}
const _IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg"]


# =================
# Primary Functions
# =================

## Maps each recognised file name to its role. Where two files claim one role the
## alphabetically first wins, so the result never depends on directory order.
static func discover_roles(file_names: PackedStringArray) -> Dictionary:
	var found := {}
	var sorted_names := Array(file_names)
	sorted_names.sort()
	for file_name: String in sorted_names:
		# Role for this file name (-1 when it is not a PBR map) so only real maps are kept.
		var role := _role_for_file(file_name)
		if role >= 0 and not found.has(role):
			found[role] = file_name
	return found


## True for a layer size the pipeline can use: block compression works on 4x4
## texel blocks, so the size must be a multiple of 4.
static func is_valid_size(size: int) -> bool:
	return size >= 4 and size % 4 == 0


## Packs loaded source images (Role int -> Image) into the three set maps.
## `force_flip_normal` inverts green even for an OpenGL-labelled normal, for
## sources of unknown convention. Returns {"error": String} when there is no albedo.
static func pack_set(images: Dictionary, size: int, force_flip_normal: bool = false) -> Dictionary:
	if not images.has(Role.ALBEDO):
		return {"error": "no albedo map found (expected a *_Color, basecolor or albedo image)"}
	# Albedo resized to the shared layer size and reduced to RGB so every packed albedo compresses to one format.
	var albedo := prepare_albedo(images[Role.ALBEDO], size)
	# Normal: OpenGL preferred, DirectX converted by a green flip, none defaults to a flat normal.
	var normal := prepare_normal(_normal_source(images), size, _normal_needs_flip(images, force_flip_normal))
	# ORME: a pre-packed source wins, otherwise the separate maps are interleaved with neutral defaults.
	var orme := _orme_from(images, size)
	# Names of the maps that had to be defaulted, so the CLI can tell the author.
	var missing := missing_maps(images)
	return {"albedo": albedo, "normal": normal, "orme": orme, "missing": missing}


## The all-neutral set at `size`: white albedo, flat normal, unoccluded rough
## non-metal ORME. Used as the fill for unset maps in Texture2DArray layers.
static func neutral_set(size: int) -> Dictionary:
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	albedo.fill(Color.WHITE)
	var orme := Image.create(size, size, false, Image.FORMAT_RGBA8)
	orme.fill(PbrTextureSet.NEUTRAL_ORME)
	return {"albedo": albedo, "normal": flat_normal(size), "orme": orme, "missing": PackedStringArray()}


## Albedo at `size`, RGB only.
static func prepare_albedo(image: Image, size: int) -> Image:
	var out := _resized(image, size)
	out.convert(Image.FORMAT_RGB8)
	return out


## Normal at `size`, RGB. A null source is a flat normal; `flip_green` converts
## a DirectX (Y-down) map to OpenGL (Y-up). A resized normal is renormalized
## because Lanczos averaging shortens the vectors, which would read as weaker bumps.
static func prepare_normal(image: Image, size: int, flip_green: bool) -> Image:
	if image == null:
		return flat_normal(size)
	var was_resized := image.get_width() != size or image.get_height() != size
	var out := _resized(image, size)
	out.convert(Image.FORMAT_RGB8)
	if flip_green:
		# Green byte of every pixel inverted: the DirectX-to-OpenGL conversion.
		out = _with_inverted_green(out)
	if was_resized:
		# Unit length restored after the downscale so the shader's Z rebuild stays accurate.
		out = _renormalized(out)
	return out


## A flat tangent-space normal map (no bumps).
static func flat_normal(size: int) -> Image:
	var out := Image.create(size, size, false, Image.FORMAT_RGB8)
	out.fill(PbrTextureSet.NEUTRAL_NORMAL)
	return out


## Interleaves separate maps into ORME (R = AO, G = roughness, B = metalness,
## A = 0). A null map becomes a constant fill from the neutral ORME, so the
## result renders exactly as an unmapped material would for that channel.
static func pack_orme(ao: Image, roughness: Image, metalness: Image, size: int) -> Image:
	# One byte per pixel per channel, or a neutral constant for a missing map.
	var ao_bytes := _channel_bytes(ao, size, _neutral_byte(PbrTextureSet.NEUTRAL_ORME.r))
	var roughness_bytes := _channel_bytes(roughness, size, _neutral_byte(PbrTextureSet.NEUTRAL_ORME.g))
	var metalness_bytes := _channel_bytes(metalness, size, _neutral_byte(PbrTextureSet.NEUTRAL_ORME.b))
	# Interleave into one RGBA8 buffer with the reserved Extra channel left at 0.
	var data := _interleave_orme(ao_bytes, roughness_bytes, metalness_bytes)
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)


## A source that is already ORME-packed: resized, with Extra (A) forced to 0 (a
## source alpha of 255 would otherwise read as full emission to a future consumer).
static func prepare_prepacked_orme(image: Image, size: int) -> Image:
	var out := _resized(image, size)
	out.convert(Image.FORMAT_RGBA8)
	var data := out.get_data()
	for i: int in range(3, data.size(), 4):
		data[i] = 0
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)


## Names of the maps the source lacked and the packer defaulted.
static func missing_maps(images: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	if not images.has(Role.NORMAL_GL) and not images.has(Role.NORMAL_DX):
		missing.append("normal")
	if images.has(Role.ORME):
		return missing
	if not images.has(Role.AMBIENT_OCCLUSION):
		missing.append("ambient occlusion")
	if not images.has(Role.ROUGHNESS):
		missing.append("roughness")
	if not images.has(Role.METALNESS):
		missing.append("metalness")
	return missing


# ===================
# Auxiliary Functions
# ===================

static func _role_for_file(file_name: String) -> int:
	if not _IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
		return -1
	var parts := file_name.get_basename().to_lower().split("_")
	var token := parts[parts.size() - 1]
	for role: int in _ROLE_TOKENS:
		if (_ROLE_TOKENS[role] as Array).has(token):
			return role
	return -1


static func _normal_source(images: Dictionary) -> Image:
	if images.has(Role.NORMAL_GL):
		return images[Role.NORMAL_GL]
	if images.has(Role.NORMAL_DX):
		return images[Role.NORMAL_DX]
	return null


static func _normal_needs_flip(images: Dictionary, force_flip_normal: bool) -> bool:
	var directx_only := images.has(Role.NORMAL_DX) and not images.has(Role.NORMAL_GL)
	return directx_only or (force_flip_normal and _normal_source(images) != null)


static func _orme_from(images: Dictionary, size: int) -> Image:
	if images.has(Role.ORME):
		return prepare_prepacked_orme(images[Role.ORME], size)
	return pack_orme(
		images.get(Role.AMBIENT_OCCLUSION), images.get(Role.ROUGHNESS), images.get(Role.METALNESS), size)


static func _resized(image: Image, size: int) -> Image:
	var out := image.duplicate() as Image
	if out.get_width() != size or out.get_height() != size:
		out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return out


static func _with_inverted_green(image: Image) -> Image:
	var data := image.get_data()
	for i: int in range(1, data.size(), 3):
		data[i] = 255 - data[i]
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, data)


static func _renormalized(image: Image) -> Image:
	var data := image.get_data()
	for i: int in range(0, data.size(), 3):
		var x := float(data[i]) / 127.5 - 1.0
		var y := float(data[i + 1]) / 127.5 - 1.0
		var z := float(data[i + 2]) / 127.5 - 1.0
		var length := sqrt(x * x + y * y + z * z)
		if length > 0.0001:
			data[i] = _unit_to_byte(x / length)
			data[i + 1] = _unit_to_byte(y / length)
			data[i + 2] = _unit_to_byte(z / length)
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, data)


static func _unit_to_byte(component: float) -> int:
	return clampi(roundi((component + 1.0) * 127.5), 0, 255)


static func _neutral_byte(value: float) -> int:
	return roundi(clampf(value, 0.0, 1.0) * 255.0)


static func _channel_bytes(image: Image, size: int, fill: int) -> PackedByteArray:
	if image == null:
		var filled := PackedByteArray()
		filled.resize(size * size)
		filled.fill(fill)
		return filled
	var gray := _resized(image, size)
	gray.convert(Image.FORMAT_L8)
	return gray.get_data()


static func _interleave_orme(ao: PackedByteArray, roughness: PackedByteArray, metalness: PackedByteArray) -> PackedByteArray:
	var count := ao.size()
	var data := PackedByteArray()
	# resize() zero-fills, which is the reserved Extra channel's value.
	data.resize(count * 4)
	for i: int in count:
		data[i * 4] = ao[i]
		data[i * 4 + 1] = roughness[i]
		data[i * 4 + 2] = metalness[i]
	return data
