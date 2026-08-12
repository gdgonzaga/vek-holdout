extends Node
## Multi-slot save/load orchestrator (ARCH `docs/architecture/save.md`).
##
## Calls each subsystem's serialize()/deserialize() — the contract established
## by RunProgress and broadened to every state-holding subsystem. Each save
## slot is a self-contained directory under `user://saves/<slot_id>/` holding
## a JSON state payload (global + per-map parked state) plus a snapshot of every
## VoxelStreamSQLite the player has touched.
##
## Three invariants keep multi-slot isolation safe (see save.md §Invariants):
##   INV-1: res:// originals are permanently read-only (SceneManager repoints
##          every stream's database_path to user:// on load).
##   INV-2: user://maps/ + this autoload's _parked dict are scratch space owned
##          by whichever slot was loaded last. Cross-slot isolation comes from
##          wipe-on-load discipline, not per-slot paths.
##   INV-3: _park_current_map() flushes BOTH the runtime sqlite (block types)
##          AND the metadata dict (HP/furniture/blueprints), in that order.
##
## Autosaves on midnight (day_rolled_over hook); parks on map swap
## (map_unloading hook); manual save via pause_menu.

const _SAVES_DIR := "user://saves/"
const _FORMAT_VERSION := 1

# map_id (String) -> { voxel_hp: Dictionary,
#                      furniture: Dictionary,
#                      blueprints: Dictionary }
# Scratch metadata for the currently-loaded slot. Replaced (NOT merged) on load
# per INV-2 — never merge, or one slot's parked state leaks into another.
var _parked: Dictionary = {}

# UUID4 of the slot a save_game() writes to. Empty when no slot is active
# (shouldn't happen in-game — _start_new_game always allocates one up front).
var _active_slot: String = ""

# Player state staged during load_game; applied AFTER swap_map reparents the
# player into the scene tree. Player.deserialize needs the player in-tree to
# set global_position / camera orientation.
var _pending_player: Variant = null


func _ready() -> void:
	EventBus.day_rolled_over.connect(_on_day_rolled_over)
	EventBus.map_unloading.connect(_on_map_unloading)


# =============================================================================
# Public API
# =============================================================================

## Allocate a new slot, set it active, and clear any previous run's parked
## state (INV-2 — a new run never inherits the prior slot's scratch). Called
## by main_menu._start_new_game before RunProgress.reset_for_new_game. Returns
## the new slot id.
func create_save(display_name: String) -> String:
	var slot_id := _generate_uuid4()
	var sdir := _slot_dir(slot_id)
	DirAccess.make_dir_recursive_absolute(sdir.trim_suffix("/"))
	_parked.clear()
	_active_slot = slot_id
	GameState.set_save_slot(slot_id)
	# Write an initial meta.json so list_saves()/has_save() see the slot at once
	# even before the first save_game() call.
	_write_json(sdir + "meta.json", {
		"format_version": _FORMAT_VERSION,
		"slot_id": slot_id,
		"display_name": display_name,
		"saved_at": int(Time.get_unix_time_from_system()),
		"current_day": int(GameState.current_day),
		"current_scene_id": GameState.current_scene_id,
		"engine_version": Engine.get_version_info()["string"],
	})
	return slot_id


## Serialize current run state into _active_slot. Parks the live map first,
## then writes meta+state, then snapshots every user://maps/<id>/ into the
## slot's maps/ dir. Returns false if no active slot or any step fails.
func save_game() -> bool:
	if _active_slot == "":
		push_warning("SaveSystem.save_game(): no active slot")
		return false

	# Fold the live map's state into _parked first (INV-3: flush + capture).
	var current_id := SceneManager.get_current_scene_id()
	if current_id != "":
		_park_current_map(current_id)

	var state := {
		"format_version": _FORMAT_VERSION,
		"global": {
			"game_state":   GameState.serialize(),
			"time":         TimeSystem.serialize(),
			"run_progress": RunProgress.serialize(),
			"expeditions":  ExpeditionManager.serialize(),
			"game_log":     GameLog.serialize(),
			"player":       _serialize_player(),
		},
		"maps": _parked.duplicate(true),
	}

	var sdir := _slot_dir(_active_slot)
	var ok_meta := _write_json(sdir + "meta.json", _build_meta(state))
	var ok_state := _write_json(sdir + "state.json", state)
	if not ok_meta or not ok_state:
		return false
	_snapshot_maps_to_slot(sdir + "maps/")
	return true


## Restore a slot into live state. Replaces _parked (INV-2), wipes and
## restores user://maps/, then swaps to the saved scene — applying parked
## state INSTEAD of authored furniture replay. Returns false on missing slot,
## version mismatch, or read failure.
##
## NOTE: this is a coroutine — it awaits swap_map. Callers (a future Load
## screen) must `await SaveSystem.load_game(slot)`.
func load_game(slot: String) -> bool:
	var sdir := _slot_dir(slot)
	if not DirAccess.dir_exists_absolute(sdir):
		push_warning("SaveSystem.load_game(): slot '%s' not found" % slot)
		return false
	var meta := _read_json(sdir + "meta.json")
	var state := _read_json(sdir + "state.json")
	if state.is_empty():
		push_warning("SaveSystem.load_game(): slot '%s' state.json missing or corrupt" % slot)
		return false
	var saved_version := int(state.get("format_version", 0))
	if saved_version != _FORMAT_VERSION:
		push_warning("SaveSystem.load_game(): format version mismatch (got %d, expected %d)" \
				% [saved_version, _FORMAT_VERSION])
		return false

	# (1) Restore global autoloads. Player is staged — applied AFTER swap_map.
	var g: Dictionary = state.get("global", {})
	if g.has("game_state"):   GameState.deserialize(g["game_state"])
	if g.has("time"):         TimeSystem.deserialize(g["time"])
	if g.has("run_progress"): RunProgress.deserialize(g["run_progress"])
	if g.has("expeditions"):  ExpeditionManager.deserialize(g["expeditions"])
	if g.has("game_log"):     GameLog.deserialize(g["game_log"])
	_pending_player = g.get("player", null)

	# (2) INV-2: replace _parked (NEVER merge), set active slot.
	_parked = state.get("maps", {}).duplicate(true)
	_active_slot = slot
	GameState.set_save_slot(slot)

	# (3) INV-2: wipe scratch runtime maps, then restore from this slot.
	SceneManager.wipe_map_cache()
	_restore_maps_from_slot(sdir + "maps/")

	# (4) Do NOT emit run_started — it re-seeds RunProgress defaults; load
	# already restored RunProgress from save. swap_map awaits a frame
	# internally; awaiting here ensures the player is in the tree before
	# _restore_player runs.
	var target_scene: String = String(meta.get("current_scene_id", "base"))
	await SceneManager.swap_map(target_scene)
	if _pending_player != null:
		_restore_player(_pending_player)
		_pending_player = null
	return true


## Enumerate all save slots, newest first. Reads ONLY meta.json per slot —
## never parses state.json — so the Load screen stays cheap regardless of
## save size. Skips slot dirs with missing/unreadable meta.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var top := DirAccess.open(_SAVES_DIR)
	if top == null:
		return out
	top.list_dir_begin()
	var name := top.get_next()
	while name != "":
		if top.current_is_dir() and not name.begins_with("."):
			var meta := _read_json(_slot_dir(name) + "meta.json")
			if not meta.is_empty():
				out.append({
					"slot_id": String(meta.get("slot_id", name)),
					"display_name": String(meta.get("display_name", name)),
					"current_day": int(meta.get("current_day", 0)),
					"saved_at": int(meta.get("saved_at", 0)),
					"current_scene_id": String(meta.get("current_scene_id", "")),
				})
		name = top.get_next()
	top.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


func has_save(slot: String) -> bool:
	return DirAccess.dir_exists_absolute(_slot_dir(slot))


## Recursively remove a slot directory. The UI button that calls this lands
## with the Load screen.
func delete_save(slot: String) -> void:
	_remove_recursive(_slot_dir(slot))
	if _active_slot == slot:
		_active_slot = ""
		_parked.clear()


func get_active_slot() -> String:
	return _active_slot


## If this autoload holds parked state for `map_id`, apply it to the freshly-
## wired `map` (voxel HP + furniture + blueprints) and return true so the
## caller (SceneManager._wire_map) skips authored furniture marker replay —
## applying both would double-spawn. Returns false when no parked state exists
## for this map id (fresh New Game / first-visit POI).
func apply_parked_state_if_any(map_id: String, map: Map) -> bool:
	if not _parked.has(map_id):
		return false
	var rec: Dictionary = _parked[map_id]
	map.get_grid().deserialize(rec.get("voxel_hp", {}))
	var bc := map.find_child("BuildController") as BuildController
	if bc != null:
		if bc.furniture_layer != null and rec.has("furniture"):
			bc.furniture_layer.deserialize(rec["furniture"])
		if bc.blueprint_layer != null and rec.has("blueprints"):
			bc.blueprint_layer.deserialize(rec["blueprints"])
	return true


# =============================================================================
# Park (within-session capture)
# =============================================================================

## INV-3 critical: flush the live map's block types to its runtime sqlite, then
## capture in-memory metadata into _parked[map_id]. Called on map_unloading
## (before queue_free, which is deferred to end-of-frame) and at the start of
## save_game. Skipping either half makes the two layers of a map's state drift
## apart — furniture floating where a wall used to be, HP for missing blocks.
func _park_current_map(map_id: String) -> void:
	var map := SceneManager.get_current_map() as Map
	if map == null:
		return
	# (1) persist block types to the runtime sqlite
	var terrain := map.get_terrain()
	if terrain != null:
		terrain.save_modified_blocks()
	# (2) capture in-memory metadata
	var rec: Dictionary = {"voxel_hp": map.get_grid().serialize()}
	var bc := map.find_child("BuildController") as BuildController
	if bc != null:
		if bc.furniture_layer != null:
			rec["furniture"] = bc.furniture_layer.serialize()
		if bc.blueprint_layer != null:
			rec["blueprints"] = bc.blueprint_layer.serialize()
	_parked[map_id] = rec


func _on_map_unloading(map_id: String) -> void:
	_park_current_map(map_id)


func _on_day_rolled_over(_new_day: int) -> void:
	# Autosave at midnight (also fires after sleep, which forces midnight).
	save_game()


# =============================================================================
# Player (deferred restore)
# =============================================================================

func _serialize_player() -> Dictionary:
	var p := SceneManager.get_player()
	if p == null:
		return {}
	return p.serialize()


func _restore_player(data: Variant) -> void:
	if data == null or not (data is Dictionary):
		return
	var p := SceneManager.get_player()
	if p != null:
		p.deserialize(data)


# =============================================================================
# Snapshot / restore runtime map files (INV-2 scratch management)
# =============================================================================

## Copy every user://maps/<id>/map.sqlite into <slot_maps_dir>/<id>/map.sqlite
## so the slot owns a snapshot of each map the player has touched. Missing
## source dirs are skipped silently (the map may never have been visited).
func _snapshot_maps_to_slot(slot_maps_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(slot_maps_dir.trim_suffix("/"))
	var src := DirAccess.open("user://maps/")
	if src == null:
		return
	src.list_dir_begin()
	var name := src.get_next()
	while name != "":
		if src.current_is_dir() and not name.begins_with("."):
			var src_file := "user://maps/%s/map.sqlite" % name
			if FileAccess.file_exists(src_file):
				var dst_dir := "%s%s/" % [slot_maps_dir, name]
				DirAccess.make_dir_recursive_absolute(dst_dir.trim_suffix("/"))
				var err := DirAccess.copy_absolute(src_file, _dst_file(dst_dir, "map.sqlite"))
				if err != OK:
					push_warning("SaveSystem: failed to snapshot '%s' (error %d)" % [src_file, err])
		name = src.get_next()
	src.list_dir_end()


## Copy every <slot_maps_dir>/<id>/map.sqlite into user://maps/<id>/map.sqlite
## so the runtime cache reflects the loaded slot. Warns (doesn't crash) on a
## slot referencing a map id whose authored original no longer exists in res://.
func _restore_maps_from_slot(slot_maps_dir: String) -> void:
	var src := DirAccess.open(slot_maps_dir)
	if src == null:
		return  # slot never visited any maps; fresh res:// pulls will populate
	src.list_dir_begin()
	var name := src.get_next()
	while name != "":
		if src.current_is_dir() and not name.begins_with("."):
			var src_file := "%s%s/map.sqlite" % [slot_maps_dir, name]
			if FileAccess.file_exists(src_file):
				if not MapLibrary.has_def(name):
					push_warning("SaveSystem: slot references unknown map id '%s' (removed since save?); skipping" % name)
					name = src.get_next()
					continue
				var dst_dir := "user://maps/%s/" % name
				DirAccess.make_dir_recursive_absolute(dst_dir.trim_suffix("/"))
				var err := DirAccess.copy_absolute(src_file, _dst_file(dst_dir, "map.sqlite"))
				if err != OK:
					push_warning("SaveSystem: failed to restore '%s' (error %d)" % [src_file, err])
		name = src.get_next()
	src.list_dir_end()


# =============================================================================
# JSON I/O
# =============================================================================

func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot open '%s' for write (%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	# JSON.parse_string returns Variant (Dictionary / Array / scalar / null);
	# assign untyped so we don't trigger INFERENCE_ON_VARIANT.
	var raw = JSON.parse_string(file.get_as_text())
	file.close()
	if raw == null or not (raw is Dictionary):
		return {}
	return raw


func _build_meta(state: Dictionary) -> Dictionary:
	var g: Dictionary = state.get("global", {})
	var gs: Dictionary = g.get("game_state", {})
	return {
		"format_version": _FORMAT_VERSION,
		"slot_id": _active_slot,
		"display_name": _slot_display_name(),
		"saved_at": int(Time.get_unix_time_from_system()),
		"current_day": int(gs.get("day", GameState.current_day)),
		"current_scene_id": String(gs.get("scene_id", GameState.current_scene_id)),
		"engine_version": Engine.get_version_info()["string"],
	}


## Display name persists across saves (set at create_save); fall back to a
## day-stamped string if the slot predates display-name tracking.
func _slot_display_name() -> String:
	var meta := _read_json(_slot_dir(_active_slot) + "meta.json")
	return String(meta.get("display_name", "Day %d" % int(GameState.current_day)))


func _slot_dir(slot: String) -> String:
	return "%s%s/" % [_SAVES_DIR, slot]


# =============================================================================
# Internals
# =============================================================================

## RFC 4122 v4 UUID. Opaque slot id — robust to future rename (the user edits
## display_name, never slot_id). Generated from a randomized 16-byte buffer
## with the version and variant bits set per spec.
func _generate_uuid4() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = rng.randi() & 0xFF
	bytes[6] = (bytes[6] & 0x0F) | 0x40  # version 4
	bytes[8] = (bytes[8] & 0x3F) | 0x80  # variant 10xxxxxx (RFC 4122)
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## Resolve "user://dir/" + "file" into a single path. DirAccess.copy_absolute
## doesn't join trailing-slash dirs cleanly; helper keeps call sites readable.
func _dst_file(dir_path: String, file_name: String) -> String:
	return dir_path.trim_suffix("/") + "/" + file_name


## Recursively remove a directory tree. Mirrors SceneManager._remove_recursive
## (used by wipe_map_cache) — duplicated here so SaveSystem stays self-contained
## for the slot directory (which is outside SceneManager's user://maps/ scope).
func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.trim_suffix("/") + "/" + entry
		if dir.current_is_dir():
			_remove_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
