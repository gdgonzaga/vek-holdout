# Subsystem: Core

The root scenes, shared utilities, global UI shell, save system, and time. Other subsystems reference Core's autoloads and scenes.

## Files

| File | Type | Responsibility |
|---|---|---|
| `main.tscn` / `main.gd` | Scene/Script | Root scene; owns CanvasLayers and MapRootSlot. Bootstraps the persistent Player, loads `base_colony` on startup (throwaway auto-load — move behind a Main Menu later), and auto-discovers POI maps at boot. Does NOT contain gameplay logic. |
| `boot.tscn` (or Main as entry — TBD) | Scene | Project entry; loads Main + MainMenu. |
| `../autoloads/game_state.gd` | Autoload | Run-level state + state-change signals. Does NOT own save logic (that's SaveSystem). |
| `../autoloads/event_bus.gd` | Autoload | Cross-scene signal relay only. No state. |
| `../autoloads/scene_manager.gd` | Autoload | Map swap (base↔POI) + full-screen UI layer management + runtime SQLite stream redirect. Does NOT own UI content (each screen is its own scene) or map metadata (that's `MapLibrary`). |
| `../autoloads/save_system.gd` | Autoload | Autosave (sleep/midnight/quit) + load. Serializes run state: GameState (day/scene/slot), Colony (roster + job board + Memorial + KeyItemPool.found), voxel world, world-map reveal, player/colonist inventories + loadouts + raid stances. Does NOT decide when to save (callers do). |
| `../autoloads/time_system.gd` | Autoload | Continuous time advance; emits `day_rolled_over`. Links to Stamina accrual. |
| `../data/game_config.tres` | Data | Engine-level constants (gravity, target FPS). See [Data Schemas](data-schemas.md). |
| `../data/starting_conditions.tres` | Data | Day-1 resources/equipment/structure (GDD §9). See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `day_rolled_over(new_day)` | `time_system.gd` | SaveSystem, HUD, raids | Yes | Sleep→Day Summary, Raid Schedule |
| `day_changed(new_day)` | `game_state.gd` | HUD | No (GameState signal) | — |
| `pause_state_changed(paused)` | `game_state.gd` | All sim nodes | No (GameState signal) | Pause Menu |
| `save_slot_changed(slot)` | `game_state.gd` | SaveSystem | No (GameState signal) | New Game / Load |
| `map_loading(map_id)` | `scene_manager.gd` | HUD (loading screen, planned) | Yes | Map swap (load any map) |
| `map_loaded(map_id)` | `scene_manager.gd` | world map UI, HUD | Yes | Map swap (load any map) |
| `map_unloading(map_id)` | `scene_manager.gd` | save_system (autosave on leave, planned) | Yes | Map swap (load any map) |

## Flow Trace: Sleep → Day Summary → Save

**Trigger:** Player interacts with bed (E) while in base scene.

1. Player emits `sleep_requested` (direct ref) → Main handles.
2. Main calls `TimeSystem.advance_to_midnight()` → TimeSystem emits `day_rolled_over(new_day)` via EventBus.
3. SaveSystem listens → serializes state (GameState, Colony, voxel world) to current save slot.
4. Player Durability auto-recovers to full (MVP interim — see GDD §6.11).
5. Stamina + Breath reset to 100% for all entities (see [Energy](energy.md) subsystem Sleep flow for the canonical detail).
6. Day Summary screen opens (CanvasLayer 20) showing the day's events.
7. Player dismisses Day Summary → returns to base scene at dawn (new day).

**End state:** New day begun, state saved, Durability reset, Stamina + Breath reset to 100%, Day Summary shown.

## Flow Trace: Pause / World Map input (Esc + M)

**Trigger:** Player presses Esc or M during gameplay.

1. `Main._unhandled_input` routes both keys.
2. **Esc** — if a full-screen UI is open, `SceneManager.close_screen()` and stop (so Esc closes the world map before it ever pauses). Otherwise toggle `GameState.set_paused(not paused)` → `pause_state_changed` → simulation nodes get `process_mode = PROCESS_MODE_DISABLED`. (Pause Menu screen planned — currently a flag only.)
3. **M** (the `world_map` action) — if a screen is open, close it; otherwise `SceneManager.open_screen("world_map")` → loads `ui/world_map/world_map.tscn` into the layer-20 slot.

**End state:** World map toggles open/closed; Esc always dismisses an open screen first, then pauses.

## Flow Trace: Map swap (`swap_map`)

**Trigger:** Base boot (`main.gd`), an expedition depart/return (`ExpeditionManager`), or any caller that needs to load a map. Single entry point.

1. `SceneManager.swap_map(map_id)` looks up the `MapDef` in `MapLibrary`; emits `map_loading`.
2. Frees the current map (emits `map_unloading` first); clears scene id.
3. Instantiates `map_def.scene_path` under `MapRootSlot`; stores as current map + scene id.
4. **Runtime SQLite redirect** (`_redirect_sqlite_stream`): ensures `user://maps/<id>/` exists; if the terrain's stream is a `VoxelStreamSQLite` backed by a `res://` path, copies the pristine database to `user://maps/<id>/map.sqlite` (only if the runtime copy doesn't already exist) and repoints the stream there; if the terrain has **no stream** (the template case), injects a `VoxelStreamSQLite` pointing at the runtime path.
5. Awaits one frame (`process_frame`) — NOT for voxel writes; only so child `_ready` calls (esp. CameraRig camera build) run before wiring reads them.
6. `MapWiring.wire_build` (adapter→grid, strategy→adapter, FurnitureLayer→container) + `wire_player` (reparent persistent Player, set spawn from `SpawnHelpers` or def fallback, wire camera/exclude into BuildController, reuse the player's `VoxelViewer`).
7. Sets `GameState.map_root`; `set_scene_id`; emits `map_loaded` (world map UI repopulates, return-to-base visibility updates).

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
| `current_scene_id` | `String` | The `MapDef.id` of the current map (e.g. `"base_colony"`, a POI id). |
| `paused` | `bool` | True when any full-screen menu is open. |
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
**Used by:** `main.gd` (base boot), `ExpeditionManager` (depart/return), `main.gd._unhandled_input` (world map toggle), future callers (New Game / Continue).

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
