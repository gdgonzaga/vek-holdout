# Subsystem: Save / Load

The orchestrator that persists run state across sessions. SaveSystem is an autoload that calls each subsystem's `serialize()` / `deserialize()` methods — the contract established by `RunProgress` and broadened to every state-holding subsystem. Multi-slot; each slot is a self-contained directory holding a JSON state payload plus a per-map snapshot of every `VoxelStreamSQLite` the player has touched. Autosaves at midnight; manual save via the pause menu.

This subsystem owns the **conventions** that make multi-slot isolation safe. The serialize/deserialize building blocks live in their respective subsystems; SaveSystem never reaches into private state.

## Files

| File | Type | Responsibility |
|---|---|---|
| `../autoloads/save_system.gd` | Autoload | Orchestrator: parking, snapshot/restore, JSON I/O. Calls each subsystem's serialize/deserialize. Does NOT own the per-system serialization logic. |
| `save.md` | Doc | This file — the conventions, slot layout, state model, and flow traces. |

## Slot directory layout

Each save slot is a self-contained directory under `user://saves/`. Slot id is an opaque UUID4 (stable across renames); the user-visible name lives inside `meta.json`.

```
user://saves/
└── <slot_id>/                         # UUID4, e.g. "0a1b2c3d-..."
    ├── meta.json                      # cheap header scanned by list_saves()
    ├── state.json                     # global + per-map parked state (the payload)
    └── maps/                          # per-map sqlite snapshots
        ├── base/map.sqlite            # copy of user://maps/base/map.sqlite at save time
        └── poi_ruins/map.sqlite       # one subdir per map the player has touched
```

Rationale for one directory per slot (vs. a flat file or single shared state file): the sqlite snapshots are binary blobs that must travel with the JSON state — a save is meaningless without its terrain DBs. Co-locating them in a directory makes save/delete/copy atomic at the filesystem level.

## State model

### `meta.json` — cheap header for the Load menu

```jsonc
{
  "format_version": 1,                 // SaveSystem._FORMAT_VERSION; loader refuses mismatches
  "slot_id": "0a1b2c3d-...",           // echoes the directory name (for sanity)
  "display_name": "Night 14 Base",     // user-visible; editable in a future rename UI
  "saved_at": 1723478400,              // unix seconds (Time.get_unix_time_from_system)
  "current_day": 14,                   // mirrored from state.global.game_state for sort/display
  "current_scene_id": "base",          // which map the player was on at save
  "engine_version": "4.7.stable"       // Engine.get_version_info()["string"]
}
```

`list_saves()` reads **only** `meta.json` per slot — never parses `state.json`. This keeps the Load screen cheap regardless of save size.

### `state.json` — the full payload

Two top-level scopes, mirroring how state actually lives in memory:

```jsonc
{
  "format_version": 1,
  "global": {                          // autoloads + persistent player (slot-scoped, not map-scoped)
    "game_state":   { ... },           // GameState.serialize()   — day, scene_id
    "time":         { ... },           // TimeSystem.serialize()  — elapsed_in_day
    "run_progress": { ... },           // RunProgress.serialize() — unlocked ids
    "expeditions":  { ... },           // ExpeditionManager.serialize() — discovered_pois, on_expedition
    "game_log":     { ... },           // GameLog.serialize()     — entries buffer
    "player":       { ... }            // Player.serialize()      — pos, cam_yaw, cam_pitch, inventory
  },
  "maps": {                            // per-map state, keyed by MapDef.id
    "base": {
      "voxel_hp":   { ... },           // VoxelGrid.serialize()   — block HP only (types are in the sqlite)
      "furniture":  { ... },           // FurnitureLayer.serialize()
      "blueprints": { ... }            // BlueprintLayer.serialize()
    },
    "poi_ruins": { ... }
  }
}
```

**Why block HP is in JSON but block *types* are in the sqlite:** Zylann's `VoxelStreamSQLite` is already a binary persistence layer for terrain. Re-serializing it into JSON would duplicate gigabytes of data and lose Zylann's chunked format. The split is: sqlite owns types, SaveSystem owns everything Zylann doesn't know about (HP metadata, furniture, blueprints).

## Invariants

The three structural rules that make multi-slot isolation safe. Violating any of them causes silent cross-slot state corruption.

### INV-1: `res://` originals are permanently read-only

Authored maps at `res://data/maps/<id>/map.sqlite` are **never written at runtime**. `SceneManager._redirect_sqlite_stream()` repoints each terrain's `VoxelStreamSQLite.database_path` from `res://` to `user://maps/<id>/map.sqlite` on map load — every subsequent flush (park, save, or otherwise) lands in the runtime copy. The authored file is touched exactly once, read-only, on the initial copy. This is structural (enforced by Godot in exported builds; convention in the editor), not behavioral.

### INV-2: The runtime cache is scratch space owned by whichever slot was loaded last

`user://maps/` and SaveSystem's in-memory `_parked` dict form a single shared scratchpad. They have no concept of "which slot am I for." Cross-slot isolation comes from **wipe-on-load discipline**, not from per-slot paths inside the runtime code:

| Operation | What it does to scratch |
|---|---|
| **New Game** (`create_save` + `_start_new_game`) | Wipe `user://maps/`; clear `_parked`. Next map visit pulls fresh from `res://`. |
| **Load slot X** (`load_game(X)`) | Wipe `user://maps/`; restore from slot X's `maps/` dir; **replace** `_parked` with slot X's `state.json["maps"]` (not merge). |
| **Park** (`_park_current_map`, on `map_unloading`) | Flush current map's sqlite to `user://maps/<id>/`; capture metadata into `_parked[map_id]`. No wipe — this *is* the scratch. |

### INV-3: Park flushes both layers atomically

A map's state is split across two storage layers with different lifetimes (see State model). Park must update **both**, in order, every time:

```gdscript
func _park_current_map(map_id: String) -> void:
    # (1) persist block types to the runtime sqlite
    var terrain := map.get_terrain()
    if terrain != null:
        terrain.save_modified_blocks()
    # (2) capture in-memory metadata (HP, furniture, blueprints)
    _parked[map_id] = { ... }
```

Skipping step 1 means block-type changes are lost on `queue_free` (Zylann doesn't auto-flush). Skipping step 2 means HP/furniture/blueprint changes are lost. Either way, the two halves of a map's state drift apart — furniture floating where a wall used to be, HP recorded for blocks that no longer exist.

### What would break it

- **Skipping `wipe_map_cache()` in `load_game`** → cross-slot residue (slot 2 sees slot 1's terrain modifications).
- **Merging into `_parked` instead of replacing on load** → slot 1's parked metadata leaks into slot 2's session.
- **A future feature that writes to `res://`** (e.g. an in-editor "save back to authored map" button) — would need to be an explicit, separate code path. Currently nothing does this.
- **Loading a slot that references a removed map id** (POI deleted in an update) — restore warns and skips; if the runtime file later gets wiped, re-pull from `res://` fails silently. `load_game` should `push_warning` for unknown ids.

### Derived semantics: "last save wins"

A direct consequence of INV-2 + INV-3: if a player parks a map but quits without saving, the next load discards the park. The runtime sqlite may still hold the parked state on disk after quit, but `load_game` overwrites it with the slot's snapshot. `_parked` is RAM-only and dies with the process; load rebuilds it from `state.json`. So **load = last save, not last park** — exactly the expected "quit without saving discards changes" behavior.

## JSON conventions

Apply to every serializer, present and future:

- **`int()` cast on every integer field read from JSON.** `JSON.parse_string()` returns all numbers as float; `"current_day": 5` comes back as `5.0`. Silent breakage in dict keys, array indices, and strict-int contexts.
- **`Vector3` / `Vector3i` → `[x, y, z]` as a JSON value; `"x,y,z"` as a JSON dict key.** Never `str(Vector3i)` — the format isn't stable across Godot versions.
- **`.duplicate(true)` every collection before stuffing into the payload.** A reference can mutate mid-stringify; the save becomes corrupt.
- **Defensive `.get(key, default)` on every read.** Saves from older versions may omit fields; never index directly.
- **`_is_restoring` flag to suppress spawn side effects during deserialize.** `spawn()` / `spawn_blueprint()` may emit `furniture_placed` / `blueprint_placed` signals that trigger expensive work (NavMesh rebakes, sound effects, etc.). During bulk load these fire hundreds of times. Set the flag in `apply_parked_state_if_any`, clear it on completion.
- **`format_version` field for migration.** Loader branches on it; never remove old-version handling when adding new fields.

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `day_rolled_over(new_day)` | `time_system.gd` | SaveSystem (autosave), HUD, raids | Yes | Sleep / midnight → autosave |
| `map_unloading(map_id)` | `scene_manager.gd` | SaveSystem (park) | Yes | Map swap — capture outgoing state before `queue_free` |

The autosave-on-`map_unloading` idea (former open question) is **off** in v1 — the within-session park hook writes to scratch only, never to disk. This keeps the "park without save" scenario valid.

## Flow Trace: New Game

**Trigger:** Main Menu → New Game button.

1. `main_menu._start_new_game()` calls `SaveSystem.create_save(name)` → generates UUID4 slot id, sets `_active_slot`, **clears `_parked`** (per INV-2).
2. `RunProgress.reset_for_new_game()` (wipe earned state).
3. `EventBus.run_started.emit()` → `BuildLibrary` re-seeds default unlocks; `ExpeditionManager` resets discovered POIs. **NOT emitted on Load** (Load restores RunProgress from save; re-seeding would clobber it).
4. Discover initial POIs (`MapLibrary.get_maps_by_type(POI)` → `ExpeditionManager.discover`).
5. `SceneManager.wipe_map_cache()` → clears `user://maps/` (INV-2 New Game row).
6. `SceneManager.swap_map("base")` → first map load pulls fresh sqlite from `res://` (INV-1).
7. `SceneManager.close_screen()`.

**End state:** New slot created and active, run-scoped state reset + reseeded, base map loaded from authored original. `_parked` is empty; the base map's first park will populate it on the player's first swap away.

## Flow Trace: Save (manual or autosave)

**Trigger:** Pause Menu → Save button, OR `EventBus.day_rolled_over` (autosave at midnight).

1. `_park_current_map(current_scene_id)` → fold the live map's state into `_parked` (INV-3: flush + capture).
2. Build `state` dict from:
   - `global`: each autoload's `serialize()` + `_serialize_player()`.
   - `maps`: `_parked.duplicate(true)`.
3. Write `meta.json` + `state.json` to `user://saves/<slot>/`.
4. `_snapshot_maps_to_slot()` → `DirAccess.copy_absolute` each `user://maps/<id>/map.sqlite` into `user://saves/<slot>/maps/<id>/map.sqlite`.
5. (Optional) prune slot subdirs for maps no longer in `_parked` (deleted between saves by a future feature).

**End state:** Slot directory contains a consistent snapshot of all state. Failures in any step log a warning and return false; partial writes are acceptable because the next save overwrites.

## Flow Trace: Load

**Trigger:** Continue / Load button on a future Load screen (UI not yet implemented; `load_game(slot)` is the API).

1. Read `meta.json` + `state.json` from `user://saves/<slot>/`.
2. `format_version` check → migrate or refuse.
3. `_is_restoring = true`; restore global autoloads via `deserialize()`:
   - GameState, TimeSystem, RunProgress, ExpeditionManager, GameLog.
   - Player state is staged in `_pending_player` — restored AFTER `swap_map` (player must be in the tree).
4. **`_parked = state["maps"].duplicate(true)`** (REPLACE, per INV-2).
5. `_active_slot = slot`.
6. `SceneManager.wipe_map_cache()` (INV-2 Load row).
7. `_restore_maps_from_slot()` → copy slot's `maps/<id>/map.sqlite` into `user://maps/<id>/map.sqlite`. Warn (don't crash) on unknown map ids.
8. **Do NOT emit `run_started`** — see New Game flow step 3.
9. `await SceneManager.swap_map(meta.current_scene_id)` → the saved map loads; because its runtime sqlite already exists (step 7), `_redirect_sqlite_stream` skips the `res://` copy. `_wire_map` calls `SaveSystem.apply_parked_state_if_any(map_id, map)` — returns true, applies `_parked[map_id]` to the freshly-wired VoxelGrid/FurnitureLayer/BlueprintLayer, **skips authored furniture marker replay** (would otherwise double-spawn).
10. `_restore_player(_pending_player)` → Player is now in the tree; `deserialize` sets position + camera + inventory.
11. `_is_restoring = false`.

**End state:** All global state restored, saved map loaded with its parked state applied (not authored replay), player at saved position. Other maps in `_parked` will apply on first visit.

## Flow Trace: Within-session park

**Trigger:** `EventBus.map_unloading(map_id)` from `SceneManager.swap_map()` (player travels base↔POI).

1. SaveSystem's `_on_map_unloading(map_id)` fires synchronously, before the deferred `queue_free()` (so the map is still alive).
2. `_park_current_map(map_id)` per INV-3 — flushes sqlite, captures metadata into `_parked[map_id]`.
3. SceneManager frees the map; later, when the player returns, `_wire_map` calls `apply_parked_state_if_any` → applies `_parked[map_id]` instead of authored replay.

**End state:** The player's modifications survive the round-trip within the session. No disk I/O beyond the sqlite flush — the metadata lives in RAM until the next save. If the player quits without saving, the parked metadata is lost (RAM cleared) and the runtime sqlite's modifications are discarded on the next load (per "last save wins").

## Integration points

| Caller | How it uses SaveSystem |
|---|---|
| `SceneManager._wire_map` | After `wire_build`, calls `SaveSystem.apply_parked_state_if_any(map_id, map)`. If it returns true, skips authored furniture marker replay (avoids double-spawn on loaded saves). |
| `SceneManager._ready` (implicit via autoload order) | SaveSystem (autoload #5) comes after SceneManager (#4); safe to call `SceneManager.get_current_map()` / `get_player()` at runtime. |
| `main_menu._start_new_game` | Calls `SaveSystem.create_save(name)` before `RunProgress.reset_for_new_game()`. |
| `pause_menu._on_save_pressed` | Calls `SaveSystem.save_game()` then `SceneManager.close_screen()`. |
| `EventBus.map_unloading` | SaveSystem listens, parks the outgoing map. |
| `EventBus.day_rolled_over` | SaveSystem listens, autosaves. |

## Class Reference

### Class: SaveSystem

**Extends:** Node (autoload, position #5 in `project.godot`)
**Script:** `save_system.gd`
**Description:** Orchestrator for run-state persistence. Calls each subsystem's `serialize()` / `deserialize()`. Owns the in-memory `_parked` dict and the active slot id. Treats `user://maps/` as scratch space; snapshots into / restores from the active slot directory.
**Used by:** `SceneManager` (parked-state application), `main_menu` (create_save on New Game), `pause_menu` (save_game on Save), `EventBus.map_unloading` (park hook), `EventBus.day_rolled_over` (autosave hook).
**Lifecycle:** `_ready` connects `day_rolled_over` + `map_unloading`. All real work happens on save/load calls; `_ready` does no I/O.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `_parked` | `Dictionary` | `map_id -> {voxel_hp, furniture, blueprints}`. Scratch metadata for currently-loaded slot. Replaced (not merged) on load. |
| `_active_slot` | `String` | UUID4 of the slot a save writes to. Empty if no slot active (shouldn't happen in-game — New Game always creates one). |
| `_pending_player` | `Variant` | Staged player state during load; applied after `swap_map` reparents the player into the tree. |
| `_is_restoring` | `bool` | True during load; suppresses spawn side effects in deserializing layers. |

**Functions (public):**

| Function | Description |
|---|---|
| `create_save(display_name: String) -> String` | Allocates a new slot (UUID4), sets `_active_slot`, clears `_parked`. Returns the slot id. Called on New Game. |
| `save_game() -> bool` | Writes `_active_slot`: parks current map, builds state dict, writes `meta.json` + `state.json`, snapshots `user://maps/` into the slot. False if no active slot. |
| `load_game(slot: String) -> bool` | Restores global autoloads, replaces `_parked`, wipes + restores `user://maps/`, `swap_map`s to the saved scene, restores player. False on missing slot or version mismatch. |
| `has_save(slot: String) -> bool` | True if the slot directory exists. |
| `list_saves() -> Array[Dictionary]` | One `{slot_id, display_name, current_day, saved_at, current_scene_id}` per slot, sorted by `saved_at` desc. Reads only `meta.json`. |
| `delete_save(slot: String) -> void` | Recursively removes the slot directory. |
| `get_active_slot() -> String` | The current slot id (or empty). |
| `apply_parked_state_if_any(map_id: String, map: Map) -> bool` | If `_parked.has(map_id)`, applies voxel_hp + furniture + blueprints to the freshly-wired map; returns true. Called from `SceneManager._wire_map` to decide whether to skip authored furniture replay. |

**Functions (internal):**

| Function | Description |
|---|---|
| `_park_current_map(map_id: String) -> void` | INV-3 critical: flushes `terrain.save_modified_blocks()` then captures metadata into `_parked[map_id]`. Hooked from `map_unloading`. |
| `_on_map_unloading(map_id: String) -> void` | Listener for `EventBus.map_unloading`; calls `_park_current_map`. |
| `_on_day_rolled_over(_new_day: int) -> void` | Listener for `EventBus.day_rolled_over`; calls `save_game` (autosave). |
| `_snapshot_maps_to_slot(slot_maps_dir: String) -> void` | Copies every `user://maps/<id>/` subdir into `<slot_maps_dir>/<id>/`. |
| `_restore_maps_from_slot(slot_maps_dir: String) -> void` | Copies every `<slot_maps_dir>/<id>/map.sqlite` into `user://maps/<id>/map.sqlite`. Warns on unknown map ids. |
| `_write_json(path, data) -> bool` / `_read_json(path) -> Dictionary` | FileAccess + JSON helpers; null/parse-fault tolerant. |
| `_build_meta(state) -> Dictionary` | Composes the `meta.json` header from the just-written state. |
| `_slot_dir(slot) -> String` | `_SAVES_DIR + slot + "/"`. |

## Future considerations

- **Load menu UI** — no Load screen exists yet. When it lands, `list_saves()` feeds the slot list and a delete button wires to `delete_save()`.
- **Save-before-quit hook** — `NOTIFICATION_WM_CLOSE_REQUEST` handler in `main.gd` would call `save_game()` so window-close quits are safe. Currently no quit hook exists; defer with the Load UI.
- **Colonists wiring** — `colonist.gd` has the serialize/deserialize contract but no live instances. Wire when the Colonists subsystem ships.
- **Format migration** — `_FORMAT_VERSION` field is in place; migration helpers get added when v2 lands. Loader currently refuses mismatched versions.
- **Binary/compressed format** — JSON is debuggable; sqlite is already binary. Revisit if save size becomes a real problem (none projected — typical state.json is a few KB).
- **Autosave on `map_unloading`** — currently off (park only). If "park without save" semantics turn out to confuse players, revisit.
