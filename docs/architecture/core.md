# Subsystem: Core

The root scenes, shared utilities, global UI shell, save system, and time. Other subsystems reference Core's autoloads and scenes.

## Files

| File | Type | Responsibility |
|---|---|---|
| `main.tscn` / `main.gd` | Scene/Script | Root scene; owns CanvasLayers and MapRootSlot. Bootstraps the persistent Player. Does NOT load any map on startup — the Main Menu's New Game button drives the base load (see [UI](ui.md)). Does NOT contain gameplay logic. |
| `boot.tscn` / `boot.gd` | Scene/Script | Project entry; loads Main, then opens the Splash screen (`SceneManager.open_screen("splash")`). The Splash auto-advances to the Main Menu. |
| `../autoloads/game_state.gd` | Autoload | Run-level state + state-change signals. Does NOT own save logic (that's SaveSystem). |
| `../autoloads/event_bus.gd` | Autoload | Cross-scene signal relay only. No state. |
| `../autoloads/scene_manager.gd` | Autoload | Map swap (base↔POI) + full-screen UI layer management + runtime SQLite stream redirect. Does NOT own UI content (each screen is its own scene) or map metadata (that's `MapLibrary`). |
| `../autoloads/save_system.gd` | Autoload | Multi-slot save/load orchestrator — see [Save / Load](save.md) for the full contract, slot layout, and invariants. Autosaves on midnight (day_rolled_over hook); parks on map swap (map_unloading hook); manual save via pause menu. Does NOT decide when to save (callers do). |
| `../autoloads/time_system.gd` | Autoload | Continuous time advance; emits `day_rolled_over` at midnight. `advance_to_midnight()` is the intended sleep trigger (no gameplay caller yet). |
| `../data/game_config.tres` | Data | Engine-level constants (gravity, target FPS). See [Data Schemas](data-schemas.md). |
| `../data/starting_conditions.tres` | Data | Planned — does not exist yet. Day-1 resources/equipment/structure (GDD §9; tech-debt C7). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `day_rolled_over(new_day)` | `time_system.gd` | SaveSystem (autosave), GameLog ("Day N begins") | Yes | Sleep→Day Summary (planned), Raid Schedule (planned) |
| `day_changed(new_day)` | `game_state.gd` | *(planned: HUD day counter — not yet connected)* | No (GameState signal) | — |
| `pause_state_changed(paused)` | `game_state.gd` | All sim nodes | No (GameState signal) | Pause Menu |
| `save_slot_changed(slot)` | `game_state.gd` | SaveSystem | No (GameState signal) | New Game / Load |
| `map_loading(map_id)` | `scene_manager.gd` | — none yet (loading screen planned) | Yes | Map swap (load any map) |
| `map_loaded(map_id)` | `scene_manager.gd` | world map UI | Yes | Map swap (load any map) |
| `map_unloading(map_id)` | `scene_manager.gd` | save_system (park on leave) | Yes | Map swap — park outgoing map before `queue_free` |

## Flow Trace: Sleep → Day Summary → Save

> **Status: mostly planned, not yet wired.** Only step 3 (autosave on midnight) is live — `SaveSystem` listens to `day_rolled_over`. The trigger (`sleep_requested`), `Main` calling `advance_to_midnight()`, the Durability/Stamina/Breath resets, and the Day Summary screen are not implemented yet (`ui/day_summary/` is empty; nothing calls `advance_to_midnight` in gameplay). Kept here as the intended shape.

**Trigger:** *(planned)* Player interacts with a bed (E) while in the base scene.

1. Player emits `sleep_requested` (direct ref) → Main handles.
2. Main calls `TimeSystem.advance_to_midnight()` → TimeSystem emits `day_rolled_over(new_day)` via EventBus.
3. SaveSystem listens → serializes state (GameState, Colony, voxel world) to current save slot.
4. Player Durability auto-recovers to full (MVP interim — see GDD §6.11).
5. Stamina + Breath reset to 100% for all entities (see [Energy](energy.md) subsystem Sleep flow for the canonical detail).
6. Day Summary screen opens (CanvasLayer 20) showing the day's events.
7. Player dismisses Day Summary → returns to base scene at dawn (new day).

**End state:** New day begun, state saved, Durability reset, Stamina + Breath reset to 100%, Day Summary shown.

## Flow Trace: Boot → Splash → Main Menu → New Game

**Trigger:** Player launches the game (Play).

1. `boot.tscn` is the `run/main_scene`. `boot.gd._ready()` instantiates `main.tscn` and adds it as a child. `Main._ready()` runs synchronously during `add_child()`, handing the MapRootSlot + layer-20 CanvasLayer to `SceneManager` and registering the persistent `Player`.
2. `boot.gd` calls `SceneManager.open_screen("splash")` → loads `ui/splash/splash.tscn` into the layer-20 slot.
3. The Splash shows its image (auto-loaded from `res://assets/ui/splash.png` if present, else a solid background) and starts a `duration` timer (default 0.2s, inspector-tunable). Any key/mouse press skips early.
4. On advance, the Splash calls `SceneManager.close_screen()` then `SceneManager.open_screen("main_menu")` → loads `ui/main_menu/main_menu.tscn`.
5. Player clicks **New Game** → `main_menu.gd._start_new_game()`:
   - `SaveSystem.create_save(name)` → allocates a fresh UUID4 slot, sets it active, clears `_parked`, writes an initial `meta.json`, and calls `GameState.set_save_slot`
   - `RunProgress.reset_for_new_game()` (wipe earned state)
   - `EventBus.run_started.emit()` → `BuildLibrary` re-seeds default unlocks; `ExpeditionManager` resets discovered POIs
   - discover initial POIs (`MapLibrary.get_maps_by_type(POI)` → `ExpeditionManager.discover`)
   - `SceneManager.wipe_map_cache()` (clear `user://maps/` so the new run pulls fresh from `res://`)
   - `SceneManager.swap_map("base")` → mounts the base map, reparents the Player, wires subsystems (see "Map swap" flow)
   - `SceneManager.close_screen()` (dismiss the menu)

**End state:** Fresh save slot created and active, run-scoped state reset + reseeded, base colony loaded from its authored original, player spawned + wired, build/world-map keys live. Load does NOT go through here — it lives in `SaveSystem.load_game`, called from the Load Game screen (`ui/load_menu`).

## Flow Trace: Pause / World Map input (Esc + M)

**Trigger:** Player presses Esc, M, H, or Tab during gameplay.

1. `Main._unhandled_input` routes the keys (Esc = `ui_cancel`, M = `world_map`).
2. **Esc** — if a full-screen UI is open, `SceneManager.close_screen()` and stop (so Esc closes the world map before it ever pauses). Otherwise `SceneManager.open_screen("pause_menu")` → mounts the **layer-30** Pause overlay (see [UI](ui.md)); the pause menu's own lifecycle owns pause + cursor — its `_ready` calls `GameState.set_paused(true)` (→ `pause_state_changed` → simulation nodes get `process_mode = DISABLED`) and releases the mouse; being freed (Resume / Esc again / replaced) unpause + restores the prior cursor mode.
3. **M** (the `world_map` action) — if a screen is open, close it; otherwise `SceneManager.open_screen("world_map")` → loads `ui/world_map/world_map.tscn` into the layer-20 slot. Two more toggles follow the same open/close pattern: **H** (`log_history` → `ui/log_history/log_history.tscn`) and **Tab** (`colony_management` → the colony overview screen with roster/labor/station/storage tabs).

**End state:** World map / log history / colony management toggle open/closed; Esc always dismisses an open screen first, then opens the Pause overlay.

## Flow Trace: Map swap (`swap_map`)

**Trigger:** Main Menu "New Game" (`main_menu.gd`), an expedition depart/return (`ExpeditionManager`), or any caller that needs to load a map. Single entry point.

1. `SceneManager.swap_map(map_id)` looks up the `MapDef` in `MapLibrary`; emits `map_loading`.
2. Frees the current map (emits `map_unloading` first); clears scene id.
3. Instantiates `map_def.scene_path` under `MapRootSlot`; stores as current map + scene id.
4. **Runtime SQLite redirect** (`_redirect_sqlite_stream`): ensures `user://maps/<id>/` exists; if the terrain's stream is a `VoxelStreamSQLite` backed by a `res://` path, copies the pristine database to `user://maps/<id>/map.sqlite` (only if the runtime copy doesn't already exist) and repoints the stream there; if the terrain has **no stream** (the template case), injects a `VoxelStreamSQLite` pointing at the runtime path.
5. Awaits one frame (`process_frame`) — NOT for voxel writes; only so child `_ready` calls (esp. CameraRig camera build) run before wiring reads them.
6. `MapWiring.wire_build` (adapter→grid, FurnitureLayer→container, BlueprintLayer→container/grid/furniture, `BlueprintPlacementStrategy`→blueprint_layer) + `wire_player` (reparent persistent Player, set spawn from `SpawnHelpers` or def fallback, wire camera/exclude into BuildController, reuse the player's `VoxelViewer`).
7. **Parked-state / authored-furniture branch:** `SaveSystem.apply_parked_state_if_any(map_id, map)` — if this map has parked state (a loaded save), it applies voxel HP + furniture + blueprints and the wiring **skips** authored `Furniture_*` marker replay (`SpawnHelpers.clear_furniture_markers`); otherwise the authored markers are replayed through `FurnitureLayer.spawn` and then cleared (avoids double-spawn).
8. Sets `GameState.map_root`; `set_scene_id`; emits `map_loaded` (world map UI repopulates, return-to-base visibility updates).

**End state:** New map mounted, terrain streaming from its runtime `user://` copy (authored `res://` database untouched), player spawned + wired, subsystems live.

## Class Reference

### Class: GameState

**Extends:** Node
**Script:** `game_state.gd`
**Description:** Run-level state holder. Holds current day, scene ID, pause state, save slot. Emits signals on its own state changes — these are NOT routed through EventBus.
**Used by:** HUD (day/pause), all scenes (pause checks), SaveSystem.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `current_day` | `int` | [export default 1] Current in-game day. |
| `current_scene_id` | `String` | The `MapDef.id` of the current map (e.g. `"base"`, a POI id). |
| `paused` | `bool` | True when the Pause overlay is open (set by `pause_menu._ready`). World-map / log-history screens do not pause. |
| `save_slot` | `String` | Current save slot name; empty if none loaded. |
| `map_root` | `Node` | Reference to the current `Map` whose children get `process_mode`-toggled on pause. Set by SceneManager at swap completion; `null` until then. |

**Signals:**

| Signal | Description |
|---|---|
| `day_changed(new_day: int)` | Midnight crossed. Listeners: HUD day counter. |
| `scene_changed(scene_id: String)` | SceneManager swap completed. Listeners: HUD. |
| `pause_state_changed(paused: bool)` | Pause toggled. Listeners: all sim nodes (process_mode). |
| `save_slot_changed(slot_name: String)` | New Game / Load. Listeners: SaveSystem. |

**Functions:**

| Function | Description |
|---|---|
| `set_paused(p: bool) -> void` | Toggles pause; emits `pause_state_changed`; sets `process_mode` on `map_root` (and its children). |
| `advance_day() -> void` | Increments `current_day`; emits `day_changed`. Called by TimeSystem. |
| `set_scene_id(scene_id: String) -> void` | Sets `current_scene_id`; emits `scene_changed`. Called by SceneManager on swap completion. |
| `set_save_slot(slot_name: String) -> void` | Sets `save_slot`; emits `save_slot_changed`. Called on New Game / Load. |

### Class: SceneManager

**Extends:** Node (autoload)
**Script:** `scene_manager.gd`
**Description:** The single entry point for loading any map and managing full-screen UI. `swap_map(map_id)` looks up a `MapDef` in `MapLibrary`, frees the current map, instantiates the new scene, performs copy-on-load SQLite redirect, and wires subsystems via `MapWiring`. `open_screen` / `close_screen` manage the layer-20 UI slot.
**Used by:** `boot.gd` (open splash), `main_menu.gd` (New Game → swap_map), `load_menu.gd` (Load → `SaveSystem.load_game` → `swap_map`), `ExpeditionManager` (depart/return), `main.gd._unhandled_input` (world map / pause toggle), `pause_menu.gd` (Quit → `unload_current_map`), future callers (Continue).

**Functions:**

| Function | Description |
|---|---|
| `setup(map_parent: Node, ui_layer: CanvasLayer) -> void` | Wiring — Main hands over the MapRootSlot node and the layer-20 CanvasLayer. |
| `set_player(player: Player) -> void` | Wiring — registers the persistent player (reparented into each map by `_wire_map`). |
| `swap_map(scene_id: String) -> void` | The single swap point. Looks up `MapDef`, frees current map, instantiates the new scene, redirects the SQLite stream (copy-on-load), awaits one frame, wires subsystems, sets `GameState.map_root` + scene id, emits `map_loaded`. `scene_id` is a `MapDef.id`. |
| `get_current_scene_id() -> String` | The current map's id. |
| `open_screen(screen_id: String) -> void` | Loads `res://ui/<id>/<id>.tscn` into the layer-20 slot; closes any open screen first. |
| `close_screen() -> void` | Frees the current full-screen UI. |
| `is_screen_open() -> bool` | Whether a full-screen UI is currently mounted. |
| `get_current_map() -> Node` | The current `Map` node (or null). Used by SaveSystem (park/restore) and others. |
| `get_player() -> Player` | The persistent Player (registered via `set_player`). Used by SaveSystem for player serialize/deserialize. |
| `unload_current_map() -> void` | Frees the current map without loading a new one (emits `map_unloading` first). Used by the pause-menu Quit path so no sim runs under the title screen. |
| `wipe_map_cache() -> void` | Recursively clears `user://maps/` so the next load pulls fresh from `res://`. Used on New Game and on Load (INV-2 wipe-on-load). |
