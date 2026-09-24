class_name PbrPackWriter
extends RefCounted
## File IO and text templates for the offline PBR packer. The image decisions live
## in PbrPacker; this class only reads a source folder, writes the three packed
## PNGs with their `.import` sidecars, and writes the PbrTextureSet `.tres`.
##
## The `.import` sidecar is written by hand because a texture that is only ever a
## shader uniform never triggers Godot's 3D auto-detect and would stay lossless
## (the old ground orme.PNG did). A sidecar without `uid`/`path` is valid: Godot
## fills both in on the next `--import`. An existing sidecar is never
## overwritten, because that would drop its uid and break references to it.

const ASSET_ROOT := "res://assets/pbr"
const DATA_ROOT := "res://data/pbr"
## Map name -> file name inside assets/pbr/<id>/.
const MAP_FILES: Dictionary = {"albedo": "albedo.png", "normal": "normal.png", "orme": "orme.png"}
const _ID_PATTERN := "^[a-z][a-z0-9_]*$"


# =================
# Primary Functions
# =================

## True for a lower snake_case identifier (the set id, its folder and its file name).
static func is_valid_id(set_id: String) -> bool:
	var regex := RegEx.new()
	regex.compile(_ID_PATTERN)
	return regex.search(set_id) != null


## Reads a source into Role int -> Image. A file is treated as an albedo-only
## source; a folder is scanned with PbrPacker.discover_roles. Returns
## {"error": String} on an unreadable source or a non-square image.
static func load_source_images(source: String) -> Dictionary:
	if FileAccess.file_exists(source):
		# A single image is an albedo-only source, for materials downloaded as one texture.
		return _load_single_image(source)
	var dir := DirAccess.open(source)
	if dir == null:
		return {"error": "cannot open '%s' (not a file or folder)" % source}
	# Which files in the folder are which maps, so only PBR maps are decoded.
	var roles := PbrPacker.discover_roles(dir.get_files())
	return _load_role_files(source, roles)


## Writes assets/pbr/<id>/{albedo,normal,orme}.png, their sidecars, and
## data/pbr/<id>.tres (only when absent). Returns "" on success, else the error.
static func write_set(set_id: String, packed: Dictionary) -> String:
	if not is_valid_id(set_id):
		return "'%s' is not a valid id (lower snake_case, starting with a letter)" % set_id
	var folder := "%s/%s" % [ASSET_ROOT, set_id]
	# The asset folder and the data folder must exist before any file is saved.
	var dir_error := _ensure_dirs(folder)
	if dir_error != "":
		return dir_error
	for map_name: String in MAP_FILES:
		# One packed map: PNG bytes plus the import sidecar that fixes its VRAM format.
		var map_error := _write_map(folder, map_name, packed[map_name])
		if map_error != "":
			return map_error
	# The set resource that ties the three maps together (left alone when it already exists).
	return _write_set_resource(set_id)


## `.import` sidecar text: VRAM-compressed with mipmaps. Normals get the
## normal-map flag (RGTC two-channel); every other map disables it (DXT1/DXT5).
static func import_sidecar(resource_path: String, is_normal_map: bool) -> String:
	var normal_flag := 1 if is_normal_map else 2
	return "\n".join([
		"[remap]", "", "importer=\"texture\"", "type=\"CompressedTexture2D\"", "",
		"[deps]", "", "source_file=\"%s\"" % resource_path, "",
		"[params]", "",
		"compress/mode=2", "compress/high_quality=false", "compress/lossy_quality=0.7",
		"compress/hdr_compression=1", "compress/normal_map=%d" % normal_flag,
		"mipmaps/generate=true", "mipmaps/limit=-1",
		"process/fix_alpha_border=false", "process/premult_alpha=false",
		"process/normal_map_invert_y=false", "process/size_limit=0", "detect_3d/compress_to=0", "",
	])


## The PbrTextureSet `.tres` text. Textures are referenced by path (no uid): the
## editor adds uids the next time it resaves the file.
static func set_resource_text(set_id: String) -> String:
	var root := "%s/%s" % [ASSET_ROOT, set_id]
	return "\n".join([
		"[gd_resource type=\"Resource\" script_class=\"PbrTextureSet\" format=3]", "",
		"[ext_resource type=\"Script\" path=\"res://data/pbr/pbr_texture_set.gd\" id=\"1_script\"]",
		"[ext_resource type=\"Texture2D\" path=\"%s/albedo.png\" id=\"2_albedo\"]" % root,
		"[ext_resource type=\"Texture2D\" path=\"%s/normal.png\" id=\"3_normal\"]" % root,
		"[ext_resource type=\"Texture2D\" path=\"%s/orme.png\" id=\"4_orme\"]" % root, "",
		"[resource]", "script = ExtResource(\"1_script\")", "id = \"%s\"" % set_id,
		"albedo = ExtResource(\"2_albedo\")", "normal = ExtResource(\"3_normal\")",
		"orme = ExtResource(\"4_orme\")", "",
	])


# ===================
# Auxiliary Functions
# ===================

static func _load_single_image(path: String) -> Dictionary:
	# Globalized so a res:// source is read as a plain file (a res:// path logs an export warning per image).
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return {"error": "cannot decode image '%s'" % path}
	if image.get_width() != image.get_height():
		return {"error": "'%s' is %dx%d; maps must be square" % [path, image.get_width(), image.get_height()]}
	return {PbrPacker.Role.ALBEDO: image}


static func _load_role_files(folder: String, roles: Dictionary) -> Dictionary:
	var images := {}
	for role: int in roles:
		var path := folder.path_join(roles[role])
		# Decode and square-check this one file so a bad map is named in the error.
		var loaded := _load_single_image(path)
		if loaded.has("error"):
			return loaded
		images[role] = loaded[PbrPacker.Role.ALBEDO]
	return images


static func _ensure_dirs(asset_folder: String) -> String:
	for path: String in [asset_folder, DATA_ROOT]:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			return "cannot create '%s' (error %d)" % [path, error]
	return ""


static func _write_map(folder: String, map_name: String, image: Image) -> String:
	var path := "%s/%s" % [folder, MAP_FILES[map_name]]
	var error := image.save_png(path)
	if error != OK:
		return "cannot write '%s' (error %d)" % [path, error]
	# Sidecar next to the PNG, skipped when one exists so the texture's uid survives a re-pack.
	return _write_sidecar_if_missing(path, map_name == "normal")


static func _write_sidecar_if_missing(png_path: String, is_normal_map: bool) -> String:
	var sidecar_path := png_path + ".import"
	if FileAccess.file_exists(sidecar_path):
		return ""
	return _write_text(sidecar_path, import_sidecar(png_path, is_normal_map))


static func _write_set_resource(set_id: String) -> String:
	var path := "%s/%s.tres" % [DATA_ROOT, set_id]
	if FileAccess.file_exists(path):
		return ""
	return _write_text(path, set_resource_text(set_id))


static func _write_text(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write '%s' (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(text)
	return ""
