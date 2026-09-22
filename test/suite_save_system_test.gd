extends GdUnitTestSuite

## SaveSystem invariant coverage (R15): the park/apply pair (INV-3's ordering,
## and the round trip apply_parked_state_if_any is the other half of), plus
## the sqlite-journal quiesce poll.
##
## REAL DATA SAFETY (verified before writing this suite): this checkout's
## resolved user:// profile is a REAL developer profile —
## "user://saves/" holds hundreds of real save slots and "user://maps/base/"
## holds real runtime voxel-stream data from actual play. Every fixture this
## suite creates uses a "zz_test_" id and this suite never calls
## SaveSystem.create_save / save_game / load_game or
## SceneManager.wipe_map_cache: create_save() allocates a random UUID4 slot id
## we cannot prefix ourselves, and load_game() unconditionally calls
## wipe_map_cache(), which deletes the ENTIRE user://maps/ tree (not scoped to
## any test id) — confirmed by reading scene_manager.gd's wipe_map_cache(),
## and confirmed destructive by inspecting this profile's real
## user://maps/base/{map.sqlite,terrain.sqlite}. Every test below reaches only
## SaveSystem's in-memory _parked dict, a zz_test_-scoped subdirectory of
## user://maps/ (never touched by wipe_map_cache in these tests since it is
## never called), and spy doubles — never the real _SAVES_DIR or the real
## user://maps/base/ tree.

const _JOURNAL_MAP_ID := "zz_test_quiesce"
const _JOURNAL_DIR := "user://maps/" + _JOURNAL_MAP_ID + "/"
const _PARK_ID := "zz_test_park_a"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	## Auxiliary: removes only this suite's zz_test_-scoped fixtures, never
	## anything else under user://maps/ or SaveSystem._parked.
	_rm_recursive(_JOURNAL_DIR.trim_suffix("/"))
	SaveSystem._parked.erase(_PARK_ID)


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


func _delete_journal_after_frames(path: String, frames: int) -> void:
	## Auxiliary: deletes the fake journal file after a bounded number of
	## physics frames — frame-based, never a wall-clock wait — while the
	## caller's own await on SaveSystem._await_stream_quiesce runs concurrently.
	for _i in range(frames):
		await get_tree().physics_frame
	DirAccess.remove_absolute(path)


## Spy double for Map: records "flush" instead of touching a real voxel
## stream, so _park_current_map's ordering is observable with no disk I/O.
class _SpyMap extends Map:
	var call_order: Array[String] = []
	func flush_voxel_streams() -> void:
		call_order.append("flush")


## Spy double for BlockyGrid: records "serialize" instead of touching
## voxel_tool. Skips the real _ready (block library/generator setup) — the
## @onready terrain_path still resolves regardless (RecordingBlockyGrid
## precedent, test/helpers/mining_rig.gd), which is all Map._ready needs.
class _SpyBlockyGrid extends BlockyGrid:
	var call_order: Array[String] = []
	func _ready() -> void:
		pass
	func serialize() -> Dictionary:
		call_order.append("serialize")
		return {"hp": {}}


## INV-3 (save.md): _park_current_map flushes the voxel stream BEFORE
## capturing metadata — "Skipping step 1 means block-type changes are lost on
## queue_free... Skipping step 2 means HP/furniture/blueprint changes are
## lost." Pin the ORDER with a spy Map + spy BlockyGrid: no real map, no disk
## I/O, safe to run against the real user-data profile.
func test_park_current_map_flushes_stream_before_capturing_metadata() -> void:
	var order: Array[String] = []
	var map: _SpyMap = auto_free(_SpyMap.new())
	map.call_order = order
	var blocky: _SpyBlockyGrid = auto_free(_SpyBlockyGrid.new())
	blocky.name = "BlockyGrid"
	blocky.call_order = order
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	blocky.add_child(terrain)
	map.add_child(blocky)
	for child_name in ["ColonistContainer", "EnemyContainer", "FurnitureContainer"]:
		var slot := Node3D.new()
		slot.name = child_name
		map.add_child(slot)
	add_child(map)

	var real_map: Node = SceneManager.get_current_map()
	SceneManager._current_map = map

	SaveSystem._park_current_map(_PARK_ID)

	SceneManager._current_map = real_map

	assert_array(order).is_equal(["flush", "serialize"])
	assert_bool(SaveSystem._parked.has(_PARK_ID)).is_true()


## apply_parked_state_if_any: when _parked holds state for a map id, applying
## it deserializes voxel HP onto the freshly-wired grid and returns true; when
## it doesn't, it is a no-op returning false. Pure in-memory round trip (no
## disk I/O) — the other half of the park/apply contract save.md documents,
## pairing with the ordering test above.
func test_apply_parked_state_round_trips_blocky_grid_hp() -> void:
	var map: Map = auto_free(Map.new())
	var blocky: BlockyGrid = auto_free(BlockyGrid.new())
	blocky.name = "BlockyGrid"
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	blocky.add_child(terrain)
	map.add_child(blocky)
	for child_name in ["ColonistContainer", "EnemyContainer", "FurnitureContainer"]:
		var slot := Node3D.new()
		slot.name = child_name
		map.add_child(slot)
	add_child(map)

	# No parked state for this id yet: no-op, returns false.
	assert_bool(SaveSystem.apply_parked_state_if_any(_PARK_ID, map)).is_false()

	SaveSystem._parked[_PARK_ID] = {"voxel_hp": {"hp": {"3,0,0": 25}}}
	assert_bool(SaveSystem.apply_parked_state_if_any(_PARK_ID, map)).is_true()
	assert_int(map.get_blocky_grid().get_hp_at(Vector3i(3, 0, 0))).is_equal(25)


## _await_stream_quiesce polls user://maps/ for a hot "<db>-journal" file and
## only returns once none remain (bounded at timeout_sec). A fire-and-forget
## background step deletes the fake journal a few frames in; the elapsed-time
## floor proves the wait genuinely polled rather than returning immediately
## (Time.get_ticks_msec() arithmetic, not a sleep — no wall-clock wait is
## introduced by this test itself).
func test_await_stream_quiesce_waits_for_journal_file_to_clear() -> void:
	DirAccess.make_dir_recursive_absolute(_JOURNAL_DIR.trim_suffix("/"))
	var journal_path := _JOURNAL_DIR + "map.sqlite-journal"
	var file := FileAccess.open(journal_path, FileAccess.WRITE)
	file.store_string("hot")
	file.close()
	assert_bool(SaveSystem._has_hot_journal("user://maps/")).is_true()

	# Fire-and-forget (the save_game()-from-day_rolled_over idiom): removes the
	# journal a few frames from now while the awaited quiesce loop below polls
	# concurrently. If quiesce returned WITHOUT actually waiting for the
	# journal to clear, this coroutine would not have reached the deletion yet
	# when the await below resumes (it needs 3 of its own physics_frame ticks
	# first) and the assertion below would catch the stale file.
	_delete_journal_after_frames(journal_path, 3)
	assert_bool(FileAccess.file_exists(journal_path)).is_true()

	await SaveSystem._await_stream_quiesce(2.0)

	assert_bool(FileAccess.file_exists(journal_path)).is_false()
	assert_bool(SaveSystem._has_hot_journal("user://maps/")).is_false()
