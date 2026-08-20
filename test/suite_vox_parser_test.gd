extends GdUnitTestSuite

const FIXTURE_PATH := "res://test/fixtures/test_cube.vox"


func test_parse_file_fixture_test_cube() -> void:
	var vox_data: VoxData = VoxParser.parse_file(FIXTURE_PATH)
	assert_object(vox_data).is_not_null()

	# Dimensions in Godot space: X=width(2), Y=height(2), Z=depth(2)
	assert_vector(vox_data.dimensions).is_equal(Vector3i(2, 2, 2))
	assert_int(vox_data.get_voxel_count()).is_equal(8)

	# Bottom layer (Godot Y=0, MV Z=0) has color index 1 (Red)
	assert_int(vox_data.get_voxel(Vector3i(0, 0, 0))).is_equal(1)
	assert_int(vox_data.get_voxel(Vector3i(1, 0, 0))).is_equal(1)
	assert_int(vox_data.get_voxel(Vector3i(0, 0, 1))).is_equal(1)
	assert_int(vox_data.get_voxel(Vector3i(1, 0, 1))).is_equal(1)

	# Top layer (Godot Y=1, MV Z=1) has color index 2 (Blue)
	assert_int(vox_data.get_voxel(Vector3i(0, 1, 0))).is_equal(2)
	assert_int(vox_data.get_voxel(Vector3i(1, 1, 0))).is_equal(2)
	assert_int(vox_data.get_voxel(Vector3i(0, 1, 1))).is_equal(2)
	assert_int(vox_data.get_voxel(Vector3i(1, 1, 1))).is_equal(2)

	# Empty voxel queries return 0
	assert_int(vox_data.get_voxel(Vector3i(5, 5, 5))).is_equal(0)
	assert_bool(vox_data.has_voxel(Vector3i(0, 0, 0))).is_true()
	assert_bool(vox_data.has_voxel(Vector3i(5, 5, 5))).is_false()

	# Palette extraction
	assert_int(vox_data.palette.size()).is_equal(256)
	var col_red := vox_data.get_color(1)
	assert_float(col_red.r).is_equal_approx(1.0, 0.01)
	assert_float(col_red.g).is_equal_approx(0.0, 0.01)
	assert_float(col_red.b).is_equal_approx(0.0, 0.01)

	var col_blue := vox_data.get_color(2)
	assert_float(col_blue.r).is_equal_approx(0.0, 0.01)
	assert_float(col_blue.g).is_equal_approx(0.0, 0.01)
	assert_float(col_blue.b).is_equal_approx(1.0, 0.01)

	# Hex matching
	assert_str(vox_data.get_hex_color(1).to_upper()).is_equal("FF0000")
	assert_str(vox_data.get_hex_color(2).to_upper()).is_equal("0000FF")

	# Used color indices
	var used := vox_data.get_used_color_indices()
	assert_int(used.size()).is_equal(2)
	assert_int(used[0]).is_equal(1)
	assert_int(used[1]).is_equal(2)


func test_parse_non_existent_file() -> void:
	var vox_data: VoxData = VoxParser.parse_file("res://does_not_exist_xyz.vox")
	assert_object(vox_data).is_null()


func test_parse_corrupted_buffer() -> void:
	var bad_buf := PackedByteArray([1, 2, 3, 4, 5])
	var vox_data: VoxData = VoxParser.parse_buffer(bad_buf)
	assert_object(vox_data).is_null()

	var bad_magic := "INVALID_HEADER_DATA".to_ascii_buffer()
	var vox_data2: VoxData = VoxParser.parse_buffer(bad_magic)
	assert_object(vox_data2).is_null()


func test_parse_without_rgba_uses_default_palette() -> void:
	# Build a minimal valid VOX buffer without RGBA chunk
	var peer := StreamPeerBuffer.new()
	peer.big_endian = false

	# Header: VOX  + version 150
	peer.put_data("VOX ".to_ascii_buffer())
	peer.put_32(150)

	# SIZE chunk
	var size_peer := StreamPeerBuffer.new()
	size_peer.big_endian = false
	size_peer.put_32(1) # x
	size_peer.put_32(1) # y
	size_peer.put_32(1) # z
	var size_data := size_peer.data_array

	# XYZI chunk
	var xyzi_peer := StreamPeerBuffer.new()
	xyzi_peer.big_endian = false
	xyzi_peer.put_32(1) # num_voxels
	xyzi_peer.put_u8(0) # x
	xyzi_peer.put_u8(0) # y
	xyzi_peer.put_u8(0) # z
	xyzi_peer.put_u8(1) # color index 1
	var xyzi_data := xyzi_peer.data_array

	# Construct children for MAIN
	var children_peer := StreamPeerBuffer.new()
	children_peer.big_endian = false

	children_peer.put_data("SIZE".to_ascii_buffer())
	children_peer.put_u32(size_data.size())
	children_peer.put_u32(0)
	children_peer.put_data(size_data)

	children_peer.put_data("XYZI".to_ascii_buffer())
	children_peer.put_u32(xyzi_data.size())
	children_peer.put_u32(0)
	children_peer.put_data(xyzi_data)

	var children_data := children_peer.data_array

	# MAIN chunk
	peer.put_data("MAIN".to_ascii_buffer())
	peer.put_u32(0) # content size
	peer.put_u32(children_data.size())
	peer.put_data(children_data)

	var vox_data: VoxData = VoxParser.parse_buffer(peer.data_array)
	assert_object(vox_data).is_not_null()
	assert_vector(vox_data.dimensions).is_equal(Vector3i(1, 1, 1))
	assert_int(vox_data.get_voxel(Vector3i(0, 0, 0))).is_equal(1)
	assert_int(vox_data.palette.size()).is_equal(256)


func test_parse_multi_model_scene_graph() -> void:
	# Build multi-model buffer:
	# Model 0: 1x1x1 at (0,0,0) with color 1
	# Model 1: 1x1x1 at (3,0,0) with color 2
	var peer := StreamPeerBuffer.new()
	peer.big_endian = false
	peer.put_data("VOX ".to_ascii_buffer())
	peer.put_32(150)

	var children_peer := StreamPeerBuffer.new()
	children_peer.big_endian = false

	# Model 0: SIZE + XYZI
	var s0 := _make_size_chunk(1, 1, 1)
	var x0 := _make_xyzi_chunk([Vector3i(0, 0, 0)], [1])
	children_peer.put_data(s0)
	children_peer.put_data(x0)

	# Model 1: SIZE + XYZI
	var s1 := _make_size_chunk(1, 1, 1)
	var x1 := _make_xyzi_chunk([Vector3i(0, 0, 0)], [2])
	children_peer.put_data(s1)
	children_peer.put_data(x1)

	# Scene Graph:
	# Root nTRN 0 -> nGRP 1
	var ntrn0 := _make_ntrn_chunk(0, 1, {})
	# nGRP 1 -> children [2, 3]
	var ngrp1 := _make_ngrp_chunk(1, [2, 3])
	# nTRN 2 -> nSHP 4 (trans 0 0 0) -> model 0
	var ntrn2 := _make_ntrn_chunk(2, 4, {"_t": "0 0 0"})
	var nshp4 := _make_nshp_chunk(4, [0])
	# nTRN 3 -> nSHP 5 (trans 3 0 0 in MV coords) -> model 1
	var ntrn3 := _make_ntrn_chunk(3, 5, {"_t": "3 0 0"})
	var nshp5 := _make_nshp_chunk(5, [1])

	children_peer.put_data(ntrn0)
	children_peer.put_data(ngrp1)
	children_peer.put_data(ntrn2)
	children_peer.put_data(nshp4)
	children_peer.put_data(ntrn3)
	children_peer.put_data(nshp5)

	var children_data := children_peer.data_array
	peer.put_data("MAIN".to_ascii_buffer())
	peer.put_u32(0)
	peer.put_u32(children_data.size())
	peer.put_data(children_data)

	var vox_data: VoxData = VoxParser.parse_buffer(peer.data_array)
	assert_object(vox_data).is_not_null()
	assert_vector(vox_data.dimensions).is_equal(Vector3i(4, 1, 1))
	assert_int(vox_data.get_voxel_count()).is_equal(2)
	assert_int(vox_data.get_voxel(Vector3i(0, 0, 0))).is_equal(1)
	assert_int(vox_data.get_voxel(Vector3i(3, 0, 0))).is_equal(2)


func test_vox_data_mutation_and_helpers() -> void:
	var data: VoxData = auto_free(VoxData.new())
	data.dimensions = Vector3i(4, 4, 4)
	data.set_voxel(Vector3i(1, 2, 3), 10)
	assert_bool(data.has_voxel(Vector3i(1, 2, 3))).is_true()
	assert_int(data.get_voxel(Vector3i(1, 2, 3))).is_equal(10)
	assert_int(data.get_voxel_count()).is_equal(1)

	# Erase via color_index <= 0
	data.set_voxel(Vector3i(1, 2, 3), 0)
	assert_bool(data.has_voxel(Vector3i(1, 2, 3))).is_false()
	assert_int(data.get_voxel_count()).is_equal(0)


# --- Test Helpers for Chunk Construction ---

func _make_size_chunk(x: int, y: int, z: int) -> PackedByteArray:
	var payload := StreamPeerBuffer.new()
	payload.big_endian = false
	payload.put_32(x)
	payload.put_32(y)
	payload.put_32(z)

	var chunk := StreamPeerBuffer.new()
	chunk.big_endian = false
	chunk.put_data("SIZE".to_ascii_buffer())
	chunk.put_u32(payload.data_array.size())
	chunk.put_u32(0)
	chunk.put_data(payload.data_array)
	return chunk.data_array


func _make_xyzi_chunk(positions: Array[Vector3i], colors: Array[int]) -> PackedByteArray:
	var payload := StreamPeerBuffer.new()
	payload.big_endian = false
	payload.put_32(positions.size())
	for i in range(positions.size()):
		payload.put_u8(positions[i].x)
		payload.put_u8(positions[i].y)
		payload.put_u8(positions[i].z)
		payload.put_u8(colors[i])

	var chunk := StreamPeerBuffer.new()
	chunk.big_endian = false
	chunk.put_data("XYZI".to_ascii_buffer())
	chunk.put_u32(payload.data_array.size())
	chunk.put_u32(0)
	chunk.put_data(payload.data_array)
	return chunk.data_array


func _write_dict(peer: StreamPeerBuffer, dict: Dictionary) -> void:
	peer.put_32(dict.size())
	for k: String in dict.keys():
		var kb := k.to_utf8_buffer()
		peer.put_32(kb.size())
		peer.put_data(kb)
		var vb := str(dict[k]).to_utf8_buffer()
		peer.put_32(vb.size())
		peer.put_data(vb)


func _make_ntrn_chunk(node_id: int, child_id: int, frame_dict: Dictionary) -> PackedByteArray:
	var payload := StreamPeerBuffer.new()
	payload.big_endian = false
	payload.put_32(node_id)
	_write_dict(payload, {})
	payload.put_32(child_id)
	payload.put_32(-1) # reserved
	payload.put_32(0)  # layer
	payload.put_32(1)  # num_frames
	_write_dict(payload, frame_dict)

	var chunk := StreamPeerBuffer.new()
	chunk.big_endian = false
	chunk.put_data("nTRN".to_ascii_buffer())
	chunk.put_u32(payload.data_array.size())
	chunk.put_u32(0)
	chunk.put_data(payload.data_array)
	return chunk.data_array


func _make_ngrp_chunk(node_id: int, child_ids: Array[int]) -> PackedByteArray:
	var payload := StreamPeerBuffer.new()
	payload.big_endian = false
	payload.put_32(node_id)
	_write_dict(payload, {})
	payload.put_32(child_ids.size())
	for cid: int in child_ids:
		payload.put_32(cid)

	var chunk := StreamPeerBuffer.new()
	chunk.big_endian = false
	chunk.put_data("nGRP".to_ascii_buffer())
	chunk.put_u32(payload.data_array.size())
	chunk.put_u32(0)
	chunk.put_data(payload.data_array)
	return chunk.data_array


func _make_nshp_chunk(node_id: int, model_ids: Array[int]) -> PackedByteArray:
	var payload := StreamPeerBuffer.new()
	payload.big_endian = false
	payload.put_32(node_id)
	_write_dict(payload, {})
	payload.put_32(model_ids.size())
	for mid: int in model_ids:
		payload.put_32(mid)
		_write_dict(payload, {})

	var chunk := StreamPeerBuffer.new()
	chunk.big_endian = false
	chunk.put_data("nSHP".to_ascii_buffer())
	chunk.put_u32(payload.data_array.size())
	chunk.put_u32(0)
	chunk.put_data(payload.data_array)
	return chunk.data_array
