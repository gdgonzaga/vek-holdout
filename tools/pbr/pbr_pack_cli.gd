extends SceneTree
## Packs a downloaded PBR material into a PbrTextureSet (docs/HOWTO-author-pbr-textures.md).
##
##   godot --headless --path . -s res://tools/pbr/pbr_pack_cli.gd -- <source> <id> [--size=1024] [--flip-normal-y]
##   godot --headless --path . -s res://tools/pbr/pbr_pack_cli.gd -- --neutral <id> [--size=1024]
##
## <source> is a folder of maps (ambientCG download, Realer Than Real folder) or a
## single albedo image. Writes assets/pbr/<id>/ and data/pbr/<id>.tres. Run
## `godot --headless --path . --import` afterwards so Godot compresses the maps.

const USAGE := "usage: -s res://tools/pbr/pbr_pack_cli.gd -- <source> <id> [--size=1024] [--flip-normal-y]\n       -s res://tools/pbr/pbr_pack_cli.gd -- --neutral <id> [--size=1024]"
const DEFAULT_SIZE := 1024


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


# =================
# Primary Functions
# =================

func _run(args: PackedStringArray) -> int:
	# Arguments split into flags and positionals, validated up front so nothing is written on a typo.
	var options := _parse_args(args)
	if options.has("error"):
		return _fail(options["error"], true)
	# The packed maps: neutral fill, or the source folder/file packed at the requested size.
	var packed := _build_packed(options)
	if packed.has("error"):
		return _fail(packed["error"], false)
	# PNGs, sidecars and the set .tres on disk.
	var write_error := PbrPackWriter.write_set(options["id"], packed)
	if write_error != "":
		return _fail(write_error, false)
	# What was defaulted and the two follow-up steps, so the author is never left guessing.
	_report(options, packed)
	return 0


func _parse_args(args: PackedStringArray) -> Dictionary:
	var options := {"size": DEFAULT_SIZE, "neutral": false, "flip": false}
	var positionals := PackedStringArray()
	for arg: String in args:
		if arg == "--neutral":
			options["neutral"] = true
		elif arg == "--flip-normal-y":
			options["flip"] = true
		elif arg.begins_with("--size="):
			options["size"] = int(arg.get_slice("=", 1))
		elif arg.begins_with("--"):
			return {"error": "unknown option '%s'" % arg}
		else:
			positionals.append(arg)
	return _assign_positionals(options, positionals)


func _assign_positionals(options: Dictionary, positionals: PackedStringArray) -> Dictionary:
	var expected := 1 if options["neutral"] else 2
	if positionals.size() != expected:
		return {"error": "expected %d positional argument(s), got %d" % [expected, positionals.size()]}
	options["id"] = positionals[positionals.size() - 1]
	options["source"] = "" if options["neutral"] else positionals[0]
	if not PbrPacker.is_valid_size(int(options["size"])):
		return {"error": "--size must be a multiple of 4 and at least 4"}
	return options


func _build_packed(options: Dictionary) -> Dictionary:
	var size: int = options["size"]
	if options["neutral"]:
		return PbrPacker.neutral_set(size)
	# Source files decoded and square-checked before any packing work starts.
	var images := PbrPackWriter.load_source_images(options["source"])
	if images.has("error"):
		return images
	return PbrPacker.pack_set(images, size, options["flip"])


func _report(options: Dictionary, packed: Dictionary) -> void:
	var id: String = options["id"]
	print("packed '%s' at %dx%d -> %s/%s/ and %s/%s.tres" % [
		id, options["size"], options["size"], PbrPackWriter.ASSET_ROOT, id, PbrPackWriter.DATA_ROOT, id])
	var missing: PackedStringArray = packed["missing"]
	if not missing.is_empty():
		print("  defaulted (no source map): %s" % ", ".join(missing))
	print("next: godot --headless --path . --import   then assign res://data/pbr/%s.tres to a def's `pbr`" % id)


func _fail(message: String, show_usage: bool) -> int:
	printerr("pbr_pack_cli: %s" % message)
	if show_usage:
		printerr(USAGE)
	return 1
