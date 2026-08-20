class_name VoxParser
extends RefCounted
## Pure GDScript parser for MagicaVoxel (.vox) RIFF files.
##
## Reads binary VOX files containing MAIN, SIZE, XYZI, RGBA, and scene graph chunks
## (nTRN, nGRP, nSHP). Converts voxel coordinates into Godot coordinate space
## (X=width, Y=height, Z=depth) and returns a populated VoxData instance.

const DEFAULT_PALETTE_HEX: Array[int] = [
	0x00000000, 0xffffffff, 0xffccffff, 0xff99ffff, 0xff66ffff, 0xff33ffff, 0xff00ffff, 0xffffccff,
	0xffccccff, 0xff99ccff, 0xff66ccff, 0xff33ccff, 0xff00ccff, 0xffff99ff, 0xffcc99ff, 0xff9999ff,
	0xff6699ff, 0xff3399ff, 0xff0099ff, 0xffff66ff, 0xffcc66ff, 0xff9966ff, 0xff6666ff, 0xff3366ff,
	0xff0066ff, 0xffff33ff, 0xffcc33ff, 0xff9933ff, 0xff6633ff, 0xff3333ff, 0xff0033ff, 0xffff00ff,
	0xffcc00ff, 0xff9900ff, 0xff6600ff, 0xff3300ff, 0xff0000ff, 0xffffffcc, 0xffccffcc, 0xff99ffcc,
	0xff66ffcc, 0xff33ffcc, 0xff00ffcc, 0xffffcccc, 0xffcccccc, 0xff99cccc, 0xff66cccc, 0xff33cccc,
	0xff00cccc, 0xffff99cc, 0xffcc99cc, 0xff9999cc, 0xff6699cc, 0xff3399cc, 0xff0099cc, 0xffff66cc,
	0xffcc66cc, 0xff9966cc, 0xff6666cc, 0xff3366cc, 0xff0066cc, 0xffff33cc, 0xffcc33cc, 0xff9933cc,
	0xff6633cc, 0xff3333cc, 0xff0033cc, 0xffff00cc, 0xffcc00cc, 0xff9900cc, 0xff6600cc, 0xff3300cc,
	0xff0000cc, 0xffffff99, 0xffccff99, 0xff99ff99, 0xff66ff99, 0xff33ff99, 0xff00ff99, 0xffffcc99,
	0xffcccc99, 0xff99cc99, 0xff66cc99, 0xff33cc99, 0xff00cc99, 0xffff9999, 0xffcc9999, 0xff999999,
	0xff669999, 0xff339999, 0xff009999, 0xffff6699, 0xffcc6699, 0xff996699, 0xff666699, 0xff336699,
	0xff006699, 0xffff3399, 0xffcc3399, 0xff993399, 0xff663399, 0xff333399, 0xff003399, 0xffff0099,
	0xffcc0099, 0xff990099, 0xff660099, 0xff330099, 0xff000099, 0xffffff66, 0xffccff66, 0xff99ff66,
	0xff66ff66, 0xff33ff66, 0xff00ff66, 0xffffcc66, 0xffcccc66, 0xff99cc66, 0xff66cc66, 0xff33cc66,
	0xff00cc66, 0xffff9966, 0xffcc9966, 0xff999966, 0xff669966, 0xff339966, 0xff009966, 0xffff6666,
	0xffcc6666, 0xff996666, 0xff666666, 0xff336666, 0xff006666, 0xffff3366, 0xffcc3366, 0xff993366,
	0xff663366, 0xff333366, 0xff003366, 0xffff0066, 0xffcc0066, 0xff990066, 0xff660066, 0xff330066,
	0xff000066, 0xffffff33, 0xffccff33, 0xff99ff33, 0xff66ff33, 0xff33ff33, 0xff00ff33, 0xffffcc33,
	0xffcccc33, 0xff99cc33, 0xff66cc33, 0xff33cc33, 0xff00cc33, 0xffff9933, 0xffcc9933, 0xff999933,
	0xff669933, 0xff339933, 0xff009933, 0xffff6633, 0xffcc6633, 0xff996633, 0xff666633, 0xff336633,
	0xff006633, 0xffff3333, 0xffcc3333, 0xff993333, 0xff663333, 0xff333333, 0xff003333, 0xffff0033,
	0xffcc0033, 0xff990033, 0xff660033, 0xff330033, 0xff000033, 0xffffff00, 0xffccff00, 0xff99ff00,
	0xff66ff00, 0xff33ff00, 0xff00ff00, 0xffffcc00, 0xffcccc00, 0xff99cc00, 0xff66cc00, 0xff33cc00,
	0xff00cc00, 0xffff9900, 0xffcc9900, 0xff999900, 0xff669900, 0xff339900, 0xff009900, 0xffff6600,
	0xffcc6600, 0xff996600, 0xff666600, 0xff336600, 0xff006600, 0xffff3300, 0xffcc3300, 0xff993300,
	0xff663300, 0xff333300, 0xff003300, 0xffff0000, 0xffcc0000, 0xff990000, 0xff660000, 0xff330000,
	0xff000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
]


## Parse a .vox file from disk. Returns null on failure.
static func parse_file(path: String) -> VoxData:
	if not FileAccess.file_exists(path):
		push_error("VoxParser: File not found: " + path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("VoxParser: Failed to open file: " + path)
		return null

	var buffer := file.get_buffer(file.get_length())
	return parse_buffer(buffer)


## Parse a .vox file from an in-memory byte buffer. Returns null on failure.
static func parse_buffer(buffer: PackedByteArray) -> VoxData:
	if buffer.size() < 8:
		push_error("VoxParser: Buffer too small to be a valid VOX file.")
		return null

	var peer := StreamPeerBuffer.new()
	peer.data_array = buffer
	peer.big_endian = false

	# 1. Header (8 bytes): "VOX " + version
	var magic := _read_chunk_id(peer)
	if magic != "VOX ":
		push_error("VoxParser: Invalid VOX magic header: '" + magic + "'")
		return null

	var _version := peer.get_32()

	# 2. MAIN Chunk header (12 bytes)
	if peer.get_available_bytes() < 12:
		push_error("VoxParser: File truncated before MAIN chunk header.")
		return null

	var main_id := _read_chunk_id(peer)
	if main_id != "MAIN":
		push_error("VoxParser: Expected MAIN chunk, got: " + main_id)
		return null

	var main_content_size := peer.get_u32()
	var main_children_size := peer.get_u32()
	var main_start_pos := peer.get_position()
	var main_end_pos := mini(peer.get_size(), main_start_pos + int(main_content_size) + int(main_children_size))

	# Advance past MAIN content (should be 0 bytes)
	if main_content_size > 0:
		peer.seek(peer.get_position() + int(main_content_size))

	# 3. Read child chunks
	var models: Array[Dictionary] = []
	var palette: Array[Color] = []
	var scene_nodes: Dictionary = {}

	while peer.get_position() + 12 <= main_end_pos:
		var chunk_id := _read_chunk_id(peer)
		var content_size := peer.get_u32()
		var children_size := peer.get_u32()
		var payload_start := peer.get_position()
		var next_chunk_pos := payload_start + int(content_size) + int(children_size)

		match chunk_id:
			"SIZE":
				_parse_SIZE(peer, models)
			"XYZI":
				_parse_XYZI(peer, models)
			"RGBA":
				_parse_RGBA(peer, palette)
			"nTRN":
				_parse_nTRN(peer, scene_nodes)
			"nGRP":
				_parse_nGRP(peer, scene_nodes)
			"nSHP":
				_parse_nSHP(peer, scene_nodes)
			_:
				pass # Ignore other chunks (MATL, LAYR, rOBJ, etc.)

		peer.seek(next_chunk_pos)

	# 4. Construct VoxData
	var vox_data := VoxData.new()

	# Set palette
	if palette.is_empty():
		vox_data.palette = get_default_palette()
	else:
		vox_data.palette = palette

	# Build voxel map from scene graph or direct models
	if scene_nodes.has(0):
		var world_voxels: Dictionary = {}
		_traverse_scene_graph(0, scene_nodes, models, Transform3D.IDENTITY, world_voxels)
		_build_normalized_vox_data(world_voxels, vox_data)
	elif not models.is_empty():
		_build_from_single_model(models[0], vox_data)

	return vox_data


## Generate the standard MagicaVoxel default 256-color palette.
static func get_default_palette() -> Array[Color]:
	var result: Array[Color] = []
	for hex_val: int in DEFAULT_PALETTE_HEX:
		var r := (hex_val & 0xFF) / 255.0
		var g := ((hex_val >> 8) & 0xFF) / 255.0
		var b := ((hex_val >> 16) & 0xFF) / 255.0
		var a := ((hex_val >> 24) & 0xFF) / 255.0
		result.append(Color(r, g, b, a))
	return result


# --- Internal Chunk Parsers ---

static func _parse_SIZE(peer: StreamPeerBuffer, models: Array[Dictionary]) -> void:
	var sx := peer.get_32()
	var sy := peer.get_32()
	var sz := peer.get_32()
	models.append({
		"size": Vector3i(sx, sy, sz),
		"voxels": []
	})


static func _parse_XYZI(peer: StreamPeerBuffer, models: Array[Dictionary]) -> void:
	var num_voxels := peer.get_32()
	var model_idx := models.size() - 1
	if model_idx < 0:
		return
	var model_voxels: Array = models[model_idx]["voxels"]
	for _i in range(num_voxels):
		var vx := peer.get_u8()
		var vy := peer.get_u8()
		var vz := peer.get_u8()
		var ci := peer.get_u8()
		model_voxels.append({
			"x": vx,
			"y": vy,
			"z": vz,
			"color": ci
		})


static func _parse_RGBA(peer: StreamPeerBuffer, palette: Array[Color]) -> void:
	palette.clear()
	for _i in range(256):
		var r := peer.get_u8() / 255.0
		var g := peer.get_u8() / 255.0
		var b := peer.get_u8() / 255.0
		var a := peer.get_u8() / 255.0
		palette.append(Color(r, g, b, a))


static func _parse_nTRN(peer: StreamPeerBuffer, scene_nodes: Dictionary) -> void:
	var node_id := peer.get_32()
	var node_attrs := _read_dict(peer)
	var child_node_id := peer.get_32()
	var _reserved_id := peer.get_32()
	var _layer_id := peer.get_32()
	var num_frames := peer.get_32()
	var frames: Array[Dictionary] = []
	for _f in range(num_frames):
		frames.append(_read_dict(peer))
	scene_nodes[node_id] = {
		"type": "TRN",
		"child": child_node_id,
		"frames": frames,
		"attrs": node_attrs
	}


static func _parse_nGRP(peer: StreamPeerBuffer, scene_nodes: Dictionary) -> void:
	var node_id := peer.get_32()
	var node_attrs := _read_dict(peer)
	var num_children := peer.get_32()
	var child_ids: Array[int] = []
	for _c in range(num_children):
		child_ids.append(peer.get_32())
	scene_nodes[node_id] = {
		"type": "GRP",
		"children": child_ids,
		"attrs": node_attrs
	}


static func _parse_nSHP(peer: StreamPeerBuffer, scene_nodes: Dictionary) -> void:
	var node_id := peer.get_32()
	var node_attrs := _read_dict(peer)
	var num_models := peer.get_32()
	var shp_models: Array[Dictionary] = []
	for _m in range(num_models):
		var mid := peer.get_32()
		var mattrs := _read_dict(peer)
		shp_models.append({
			"model_id": mid,
			"attrs": mattrs
		})
	scene_nodes[node_id] = {
		"type": "SHP",
		"models": shp_models,
		"attrs": node_attrs
	}


# --- Scene Graph & Coordinate Mapping Helpers ---

static func _traverse_scene_graph(
	node_id: int,
	scene_nodes: Dictionary,
	models: Array[Dictionary],
	accum_transform: Transform3D,
	world_voxels: Dictionary
) -> void:
	if not scene_nodes.has(node_id):
		return
	var node: Dictionary = scene_nodes[node_id]
	var node_type: String = node.get("type", "")

	if node_type == "TRN":
		var child_id: int = node.get("child", -1)
		var frames: Array = node.get("frames", [])
		var local_transform := Transform3D.IDENTITY
		if not frames.is_empty():
			var frame0: Dictionary = frames[0]
			var trans_str: String = frame0.get("_t", "")
			var translation := Vector3.ZERO
			if not trans_str.is_empty():
				var parts := trans_str.split(" ", false)
				if parts.size() >= 3:
					translation = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
			var rot_str: String = frame0.get("_r", "")
			var rot_byte := rot_str.to_int() if not rot_str.is_empty() else 4
			var rot_basis := _decode_rotation(rot_byte)
			local_transform = Transform3D(rot_basis, translation)

		var next_transform := accum_transform * local_transform
		_traverse_scene_graph(child_id, scene_nodes, models, next_transform, world_voxels)

	elif node_type == "GRP":
		var children: Array = node.get("children", [])
		for child_id: int in children:
			_traverse_scene_graph(child_id, scene_nodes, models, accum_transform, world_voxels)

	elif node_type == "SHP":
		var shp_models: Array = node.get("models", [])
		for sm: Dictionary in shp_models:
			var mid: int = sm.get("model_id", -1)
			if mid >= 0 and mid < models.size():
				var model_data: Dictionary = models[mid]
				var mv_size: Vector3i = model_data.get("size", Vector3i.ZERO)
				var center := Vector3(
					floor(float(mv_size.x) / 2.0),
					floor(float(mv_size.y) / 2.0),
					floor(float(mv_size.z) / 2.0)
				)
				var voxels: Array = model_data.get("voxels", [])
				for v: Dictionary in voxels:
					var vx: int = v.get("x", 0)
					var vy: int = v.get("y", 0)
					var vz: int = v.get("z", 0)
					var ci: int = v.get("color", 0)
					var local_pos := Vector3(float(vx), float(vy), float(vz)) - center
					var world_pos := accum_transform * local_pos
					# MagicaVoxel (X=width, Y=depth, Z=height) -> Godot (X=width, Y=height, Z=depth)
					var godot_world_pos := Vector3i(
						roundi(world_pos.x),
						roundi(world_pos.z),
						roundi(world_pos.y)
					)
					world_voxels[godot_world_pos] = ci


static func _build_normalized_vox_data(world_voxels: Dictionary, vox_data: VoxData) -> void:
	if world_voxels.is_empty():
		vox_data.dimensions = Vector3i.ZERO
		return

	var min_coord := Vector3i(2147483647, 2147483647, 2147483647)
	var max_coord := Vector3i(-2147483648, -2147483648, -2147483648)
	for p: Vector3i in world_voxels.keys():
		min_coord.x = mini(min_coord.x, p.x)
		min_coord.y = mini(min_coord.y, p.y)
		min_coord.z = mini(min_coord.z, p.z)
		max_coord.x = maxi(max_coord.x, p.x)
		max_coord.y = maxi(max_coord.y, p.y)
		max_coord.z = maxi(max_coord.z, p.z)

	for p: Vector3i in world_voxels.keys():
		var norm_pos := p - min_coord
		vox_data.set_voxel(norm_pos, world_voxels[p])

	vox_data.dimensions = max_coord - min_coord + Vector3i.ONE


static func _build_from_single_model(model_data: Dictionary, vox_data: VoxData) -> void:
	var mv_size: Vector3i = model_data.get("size", Vector3i.ZERO)
	# MagicaVoxel (X=width, Y=depth, Z=height) -> Godot (X=width, Y=height, Z=depth)
	vox_data.dimensions = Vector3i(mv_size.x, mv_size.z, mv_size.y)
	var voxels: Array = model_data.get("voxels", [])
	for v: Dictionary in voxels:
		var vx: int = v.get("x", 0)
		var vy: int = v.get("y", 0)
		var vz: int = v.get("z", 0)
		var ci: int = v.get("color", 0)
		vox_data.set_voxel(Vector3i(vx, vz, vy), ci)


static func _decode_rotation(r_byte: int) -> Basis:
	var r0 := r_byte & 0x03
	var r1 := (r_byte >> 2) & 0x03
	var s0 := -1.0 if ((r_byte >> 4) & 1) != 0 else 1.0
	var s1 := -1.0 if ((r_byte >> 5) & 1) != 0 else 1.0
	var s2 := -1.0 if ((r_byte >> 6) & 1) != 0 else 1.0
	var r2 := 3 - r0 - r1

	var col0 := Vector3.ZERO
	var col1 := Vector3.ZERO
	var col2 := Vector3.ZERO
	col0[r0] = s0
	col1[r1] = s1
	col2[r2] = s2

	return Basis(col0, col1, col2)


# --- Binary Reading Helpers ---

static func _read_chunk_id(peer: StreamPeerBuffer) -> String:
	var res := peer.get_data(4)
	if res[0] != OK or (res[1] as PackedByteArray).size() < 4:
		return ""
	return (res[1] as PackedByteArray).get_string_from_ascii()


static func _read_string(peer: StreamPeerBuffer) -> String:
	if peer.get_available_bytes() < 4:
		return ""
	var str_len := peer.get_32()
	if str_len <= 0 or peer.get_available_bytes() < str_len:
		return ""
	var res := peer.get_data(str_len)
	if res[0] != OK:
		return ""
	return (res[1] as PackedByteArray).get_string_from_utf8()


static func _read_dict(peer: StreamPeerBuffer) -> Dictionary:
	var dict: Dictionary = {}
	if peer.get_available_bytes() < 4:
		return dict
	var count := peer.get_32()
	for _i in range(count):
		var key := _read_string(peer)
		var val := _read_string(peer)
		dict[key] = val
	return dict
