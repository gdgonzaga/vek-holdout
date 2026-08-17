extends GdUnitTestSuite

## Dual-voxel Phase 4 two-stream persistence (docs/TODO.md): Map.persisted_streams
## is the ONE terrain<->db pairing, shared by SceneManager's copy-on-load redirect
## and SaveSystem's park flush / slot snapshot+restore. These tests pin that
## pairing, the redirect's per-stream copy/repoint/inject rules, the both-grid
## flush, and the snapshot -> wipe -> restore file round-trip. res://data/maps/
## base/map.sqlite doubles as an existing committed source for the copy branch;
## res://data/maps/dev/terrain.sqlite (deliberately not committed — the generator
## is the dev map's smooth baseline) doubles as a missing source.

const _REDIRECT_ID := "zz_streamtest"
const _RT_ID := "zz_p4rt"
const _UNKNOWN_ID := "zz_gone"
const _SCRATCH := "user://tmp_p4/"

var _registered_ids: Array[String] = []


func before_test() -> void:
	_cleanup()
	_registered_ids = []


func after_test() -> void:
	for id: String in _registered_ids:
		MapLibrary._defs_by_id.erase(id)
	_registered_ids = []
	_cleanup()


## Map with BlockyGrid (+VoxelTerrain) and the three container slots every Map
## @onready expects; optionally a live SmoothGrid (terrain_gen set before tree
## entry, else _ready frees it) with its own VoxelTerrain.
func _build_map(with_smooth: bool, smooth_gen: bool = true) -> Map:
	var map: Map = auto_free(Map.new())
	var blocky: BlockyGrid = auto_free(BlockyGrid.new())
	blocky.name = "BlockyGrid"
	var blocky_terrain := VoxelTerrain.new()
	blocky_terrain.name = "VoxelTerrain"
	blocky.add_child(blocky_terrain)
	map.add_child(blocky)
	if with_smooth:
		var smooth: SmoothGrid = auto_free(SmoothGrid.new())
		smooth.name = "SmoothGrid"
		if smooth_gen:
			var gen := TerrainGenDef.new()
			gen.noise_seed = 11
			smooth.terrain_gen = gen
		var smooth_terrain := VoxelTerrain.new()
		smooth_terrain.name = "VoxelTerrain"
		smooth.add_child(smooth_terrain)
		map.add_child(smooth)
	for child_name in ["ColonistContainer", "EnemyContainer", "FurnitureContainer"]:
		var slot := Node3D.new()
		slot.name = child_name
		map.add_child(slot)
	add_child(map)
	return map


func _sqlite_stream(db_path: String) -> VoxelStreamSQLite:
	var stream := VoxelStreamSQLite.new()
	stream.database_path = db_path
	return stream


func _write_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir().trim_suffix("/"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _rm_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.trim_suffix("/").path_join(entry)
		if dir.current_is_dir():
			_rm_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path.trim_suffix("/"))


func _cleanup() -> void:
	_rm_recursive("user://maps/" + _REDIRECT_ID)
	_rm_recursive("user://maps/" + _RT_ID)
	_rm_recursive("user://maps/" + _UNKNOWN_ID)
	_rm_recursive(_SCRATCH)


func _register_map(id: String) -> void:
	var def := MapDef.new()
	def.id = id
	MapLibrary._defs_by_id[id] = def
	_registered_ids.append(id)


## The pairing itself: blocky -> map.sqlite always; smooth -> terrain.sqlite
## only when the grid is live (terrain_gen set).
func test_persisted_streams_pairing() -> void:
	var map := _build_map(true)
	var streams: Array[Dictionary] = map.persisted_streams()
	assert_int(streams.size()).is_equal(2)
	assert_str(streams[0]["db"]).is_equal("map.sqlite")
	assert_that(streams[0]["terrain"]).is_same(map.get_blocky_terrain())
	assert_str(streams[1]["db"]).is_equal("terrain.sqlite")
	assert_that(streams[1]["terrain"]).is_same(map.get_smooth_terrain())


## A SmoothGrid without terrain_gen queued itself for deletion in _ready —
## get_smooth_terrain/persisted_streams must already treat it as gone; a map
## without the node at all answers the same way.
func test_persisted_streams_without_live_smooth() -> void:
	var freed_grid_map := _build_map(true, false)
	assert_int(freed_grid_map.persisted_streams().size()).is_equal(1)
	assert_str(freed_grid_map.persisted_streams()[0]["db"]).is_equal("map.sqlite")
	assert_object(freed_grid_map.get_smooth_terrain()).is_null()

	var no_node_map := _build_map(false)
	assert_int(no_node_map.persisted_streams().size()).is_equal(1)
	assert_object(no_node_map.get_smooth_terrain()).is_null()


## Redirect happy path for BOTH streams: existing res:// sources are copied to
## user://maps/<id>/ under their paired names and both streams repointed.
func test_redirect_copies_and_repoints_both_streams() -> void:
	var map := _build_map(true)
	map.get_blocky_terrain().stream = _sqlite_stream("res://data/maps/base/map.sqlite")
	map.get_smooth_terrain().stream = _sqlite_stream("res://data/maps/base/map.sqlite")
	SceneManager._redirect_sqlite_stream(map, _REDIRECT_ID)
	var dir := "user://maps/%s/" % _REDIRECT_ID
	assert_bool(FileAccess.file_exists(dir + "map.sqlite")).is_true()
	assert_bool(FileAccess.file_exists(dir + "terrain.sqlite")).is_true()
	assert_str((map.get_blocky_terrain().stream as VoxelStreamSQLite).database_path) \
			.is_equal(dir + "map.sqlite")
	assert_str((map.get_smooth_terrain().stream as VoxelStreamSQLite).database_path) \
			.is_equal(dir + "terrain.sqlite")


## A missing res:// source is not an error: no copy happens (the generator is
## the baseline; the runtime db appears on first save) but the stream still
## repoints so runtime edits land in user://, never res:// (INV-1).
func test_redirect_missing_source_repoints_without_copy() -> void:
	var map := _build_map(true)
	map.get_smooth_terrain().stream = _sqlite_stream("res://data/maps/dev/terrain.sqlite")
	SceneManager._redirect_sqlite_stream(map, _REDIRECT_ID)
	assert_bool(FileAccess.file_exists("user://maps/%s/terrain.sqlite" % _REDIRECT_ID)).is_false()
	assert_str((map.get_smooth_terrain().stream as VoxelStreamSQLite).database_path) \
			.is_equal("user://maps/%s/terrain.sqlite" % _REDIRECT_ID)


## Template-stamped terrains with no baked stream get one injected at the
## runtime path, both grids.
func test_redirect_injects_streams_when_absent() -> void:
	var map := _build_map(true)
	map.get_blocky_terrain().stream = null
	map.get_smooth_terrain().stream = null
	SceneManager._redirect_sqlite_stream(map, _REDIRECT_ID)
	var blocky_stream := map.get_blocky_terrain().stream as VoxelStreamSQLite
	var smooth_stream := map.get_smooth_terrain().stream as VoxelStreamSQLite
	assert_object(blocky_stream).is_not_null()
	assert_str(blocky_stream.database_path).is_equal("user://maps/%s/map.sqlite" % _REDIRECT_ID)
	assert_object(smooth_stream).is_not_null()
	assert_str(smooth_stream.database_path).is_equal("user://maps/%s/terrain.sqlite" % _REDIRECT_ID)


## An existing runtime copy is the player's progress — redirect must never
## overwrite it with the authored original.
func test_redirect_keeps_existing_runtime_copy() -> void:
	var map := _build_map(true)
	map.get_blocky_terrain().stream = _sqlite_stream("res://data/maps/base/map.sqlite")
	_write_file("user://maps/%s/map.sqlite" % _REDIRECT_ID, "player progress sentinel")
	SceneManager._redirect_sqlite_stream(map, _REDIRECT_ID)
	assert_str(_read_file("user://maps/%s/map.sqlite" % _REDIRECT_ID)) \
			.is_equal("player progress sentinel")


## flush_voxel_streams persists edits from BOTH grids into their paired dbs
## (INV-3's voxel half after Phase 4). Creation of the db files is the
## observable — zylann creates them on first block save.
func test_flush_voxel_streams_saves_both_grids() -> void:
	DirAccess.make_dir_recursive_absolute(_SCRATCH.trim_suffix("/"))
	var map := _build_map(true)
	map.get_blocky_terrain().stream = _sqlite_stream(_SCRATCH + "blocky.sqlite")
	map.get_smooth_terrain().stream = _sqlite_stream(_SCRATCH + "smooth.sqlite")
	# F3 (docs/VOXEL-TOOL-NOTES.md): writes into blocks no viewer streamed in
	# are silent no-ops — park a collision-only viewer on the edit sites and
	# let the blocks load before editing.
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = false
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	map.add_child(viewer)
	await get_tree().create_timer(0.5).timeout
	map.get_blocky_grid().set_block_at(Vector3i(2, 24, 2), "stone")
	map.get_smooth_grid().carve(Vector3(0, 4, 0), 2.5)
	await get_tree().physics_frame
	map.flush_voxel_streams()
	await get_tree().create_timer(0.6).timeout
	assert_bool(FileAccess.file_exists(_SCRATCH + "blocky.sqlite")).is_true()
	assert_bool(FileAccess.file_exists(_SCRATCH + "smooth.sqlite")).is_true()


## Snapshot -> wipe -> restore round-trips BOTH dbs with contents intact;
## unknown map ids in the slot are skipped; missing files in the slot are
## skipped silently (a smooth stream with no edits may have saved none).
func test_snapshot_restore_round_trip_both_dbs() -> void:
	_register_map(_RT_ID)
	var runtime_dir := "user://maps/%s/" % _RT_ID
	_write_file(runtime_dir + "map.sqlite", "BLOCKY-SENTINEL")
	_write_file(runtime_dir + "terrain.sqlite", "SMOOTH-SENTINEL")
	var slot_dir := _SCRATCH + "slot/maps/"

	SaveSystem._snapshot_maps_to_slot(slot_dir)
	assert_str(_read_file(slot_dir + _RT_ID + "/map.sqlite")).is_equal("BLOCKY-SENTINEL")
	assert_str(_read_file(slot_dir + _RT_ID + "/terrain.sqlite")).is_equal("SMOOTH-SENTINEL")

	_rm_recursive(runtime_dir.trim_suffix("/"))
	SaveSystem._restore_maps_from_slot(slot_dir)
	assert_str(_read_file(runtime_dir + "map.sqlite")).is_equal("BLOCKY-SENTINEL")
	assert_str(_read_file(runtime_dir + "terrain.sqlite")).is_equal("SMOOTH-SENTINEL")

	# Unknown id in the slot: skipped entirely — no runtime dir created for it,
	# while the known id still restores from the same slot.
	_write_file(slot_dir + _UNKNOWN_ID + "/map.sqlite", "ORPHAN")
	_rm_recursive(runtime_dir.trim_suffix("/"))
	SaveSystem._restore_maps_from_slot(slot_dir)
	assert_bool(DirAccess.dir_exists_absolute("user://maps/%s/" % _UNKNOWN_ID)).is_false()
	assert_str(_read_file(runtime_dir + "map.sqlite")).is_equal("BLOCKY-SENTINEL")

	# Only the smooth db in the slot: the blocky file is absent, not fabricated.
	_rm_recursive(runtime_dir.trim_suffix("/"))
	_rm_recursive((slot_dir + _RT_ID).trim_suffix("/"))
	_write_file(slot_dir + _RT_ID + "/terrain.sqlite", "SMOOTH-ONLY")
	SaveSystem._restore_maps_from_slot(slot_dir)
	assert_str(_read_file(runtime_dir + "terrain.sqlite")).is_equal("SMOOTH-ONLY")
	assert_bool(FileAccess.file_exists(runtime_dir + "map.sqlite")).is_false()
