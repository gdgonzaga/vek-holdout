# Subsystem: Core

The **Core** subsystem (`subsystems/core/`) owns the game's top-level orchestration: main scene composition, autoloads, save/load coordination, time progression, input routing, and the game loop.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/core/main.gd` / `main.tscn` | Scene/Script (`class_name Main`, autoload-adjacent root scene) | Persistent scene skeleton (`UILayer`, `HUDLayer`, `World`), creates the persistent `Player`, mounts HUD/log-feed/dig-box overlays, routes global hotkeys. |
| `subsystems/autoloads/game_state.gd` | Script (autoload `GameState`) | Run-level state holder: day, scene id, pause, save slot, pathfinding strategy, local player ref. |
| `subsystems/autoloads/scene_manager.gd` | Script (autoload `SceneManager`) | Map swap orchestrator + full-screen UI slot manager. |
| `subsystems/autoloads/time_system.gd` | Script (autoload `TimeSystem`) | Real-time-driven in-game clock; day rollover; sleep trigger. |
| `subsystems/autoloads/save_system.gd` | Script (autoload `SaveSystem`) | Save/load orchestrator — see [Save / Load](save.md) for its own page. |
| `subsystems/autoloads/event_bus.gd` | Script (autoload `EventBus`) | Cross-scene signal relay — see [Overview](overview.md) for the full registry. |
| `subsystems/core/boot.gd` / `boot.tscn` | Scene/Script (`class_name Boot`) | Project entry point (`project.godot`'s `run/main_scene`). Loads `main.tscn`, then opens the Splash screen on the UI layer. |
| `subsystems/core/debug_logger.gd` | Script (`class_name DebugLogger`, `RefCounted` static utility — not an autoload) | Structured multi-subsystem dev logging: per-subsystem enable flags, buffered file output to `user://logs/debug.log`, optional console echo. Config-driven via `data/game_config.tres`. This is *not* the planned interactive [Debug Console](debug-console.md) (that's an unbuilt command-input UI) — `DebugLogger` is a today-working, one-way log sink. |
| `subsystems/core/ground_safety_guard.gd`, `step_climber.gd`, `ghost_preview.gd` | Scripts | Ambiguous-ownership utilities that landed in `subsystems/core/` per AGENTS.md (not part of the save/scene/time orchestration above; shared by locomotion/build code elsewhere). |

Other Core-owned autoloads (`Colony`, `RunProgress`, `UiGate`, `Tools`) have their own architecture pages or are documented alongside the subsystem they serve.

---

## Signal Flow

```
+--------------------------------------------------------------------------------+
|                                CORE SIGNALS                                    |
|                                                                                |
|  TimeSystem                        GameState                  SaveSystem       |
|  day_rolled_over ----------------> day_changed                                 |
|                                    pause_state_changed                         |
|                                    save_slot_changed --------> serialize       |
|                                    pathfinding_strategy_changed                |
|                                                                                |
|  SceneManager                      EventBus                                    |
|  map_loaded ---------------------> (re-emits map_loaded,                       |
|  map_unloaded                      re-wires colonists,                         |
|                                    spawns player)                              |
+--------------------------------------------------------------------------------+
```

### Signal Registry

| Signal | Source | Listeners | EventBus? | Description / Notes |
|---|---|---|---|---|
| `day_changed(new_day)` | `game_state.gd` | *(unconnected — HUD polls `GameState.current_day` directly instead)* | No (GameState signal) | — |
| `scene_changed(scene_id)` | `game_state.gd` | *(unconnected)* | No (GameState signal) | — |
| `pause_state_changed(paused)` | `game_state.gd` | All sim nodes | No (GameState signal) | Pause Menu |
| `save_slot_changed(slot)` | `game_state.gd` | SaveSystem | No (GameState signal) | New Game / Load |
| `pathfinding_strategy_changed(new_type)` | `game_state.gd` | Colony (live agents) | No (GameState signal) | Pathfinding strategy toggle |

---

## Key Flows

### Save Game Flow

1. Player triggers Save (e.g. from Pause Menu).
2. SaveSystem calls `SaveSystem.save_game(slot_name)`.
3. SaveSystem listens -> serializes state (GameState, Colony, voxel world) to current save slot.
4. On completion, emits `save_completed(success)`.

### Load Game Flow

1. Player triggers Load from Main Menu or Pause Menu.
2. SaveSystem reads save slot data.
3. SaveSystem deserializes world and state:
   - Sets GameState properties.
   - Restores Colony roster and storage.
   - Loads voxel map.
4. On completion, emits `load_completed(success)`.

### New Game Flow

1. Player selects **New Game** in `main_menu`.
2. Main Menu calls:
   - `SaveSystem.create_save(name)` -> allocates a fresh UUID4 slot, sets it active, clears `_parked`, writes an initial `meta.json`, and calls `GameState.set_save_slot`
   - `SceneManager.swap_map(starting_map_id)` -> unloads the menu scene, loads `data/maps/<id>/map.tscn` (typically `"base"`), mounts it under `MapRoot`, connects `MapWiring`, and spawns the player at the authored spawn marker.
3. Once the map is wired, `SceneManager.close_screen()` frees the menu and locks the mouse for gameplay.

### Pause / Resume Flow

1. While playing in a map, player presses **Esc** or clicks **Pause** on the HUD.
2. **Esc** — if a full-screen UI is open, `SceneManager.close_screen()` and stop (so Esc closes the world map before it ever pauses). Otherwise `SceneManager.open_screen("pause_menu")` -> mounts the **layer-30** Pause overlay (see [UI](ui.md)); the pause menu's own lifecycle owns pause + cursor — its `_ready` calls `GameState.set_paused(true)` (-> `pause_state_changed` -> simulation nodes get `process_mode = DISABLED`) and releases the mouse; being freed (Resume / Esc again / replaced) unpause + restores the prior cursor mode.
3. **Resume** button or Esc while Pause is showing calls `SceneManager.close_screen()` -> pause menu frees -> `_exit_tree` / close path calls `GameState.set_paused(false)`.

### Map Swap Flow

1. Player interacts with a transit trigger (e.g. world-map destination, elevator, POI boundary).
2. Trigger invokes `SceneManager.swap_map(new_map_id)`.
3. SceneManager:
   - Emits `map_unloaded(old_map_id)`.
   - Park current map's runtime SQLite stream to SaveSystem.
   - Frees old map scene.
   - Instantiates new map scene from `data/maps/<new_map_id>/map.tscn`.
   - Repoints SQLite streams to user save slot copy (copy-on-load discipline).
   - Mounts map under `MapRoot`.
   - Calls `MapWiring.wire_all(...)` to connect terrain, colonists, furniture, and lighting.
   - Reparents the persistent `Player` node into the new map's `Entities` container and snaps to the target spawn marker.
4. Sets `GameState.map_root`; `set_scene_id`; emits `map_loaded` (world map UI repopulates, return-to-base visibility updates).

---

## Classes

### Class: GameState

**Extends:** Node  
**Script:** `game_state.gd`  
**Description:** Run-level state holder. Holds current day, scene ID, pause state, save slot, and global pathfinding strategy. Emits signals on its own state changes — these are NOT routed through EventBus.  
**Used by:** HUD (day/pause), all scenes (pause checks), SaveSystem, Colony.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `current_day` | `int` | [export default 1] Current in-game day. |
| `current_scene_id` | `String` | The `MapDef.id` of the current map (e.g. `"base"`, a POI id). |
| `paused` | `bool` | True when the Pause overlay is open (set by `pause_menu._ready`). World-map / log-history screens do not pause. |
| `save_slot` | `String` | Current save slot name; empty if none loaded. |
| `map_root` | `Node` | Reference to the current `Map` whose children get `process_mode`-toggled on pause. Set by SceneManager at swap completion; `null` until then. |
| `pathfinding_strategy` | `PathfindingStrategyType` | Global strategy setting: `SMOOTHED_A_STAR` (0), `A_STAR_8_WAY` (1), `A_STAR_4_WAY` (2), `THETA_STAR` (3). |
| `rng` | `RandomNumberGenerator` | Central RNG for deterministic gameplay randomness. Randomized in `_ready`. |
| `local_player` | `Node` | The active local `Player`, or `null` before spawn. Set/cleared by `Player._ready`/`_exit_tree` via `set_local_player`. Read by mining/raid code needing the player without a scene-tree lookup. |

**Signals:**

| Signal | Description |
|---|---|
| `day_changed(new_day: int)` | Midnight crossed. Unconnected — HUD reads `GameState.current_day` directly via polling instead of subscribing. |
| `scene_changed(scene_id: String)` | SceneManager swap completed. Unconnected. |
| `pause_state_changed(paused: bool)` | Pause toggled. Listeners: all sim nodes (process_mode). |
| `save_slot_changed(slot_name: String)` | New Game / Load. Listeners: SaveSystem. |
| `pathfinding_strategy_changed(new_type: int)` | Pathfinding strategy changed. Listeners: Colony. |

**Functions:**

| Function | Description |
|---|---|
| `set_paused(p: bool) -> void` | Toggles pause; emits `pause_state_changed`; sets `process_mode` on `map_root` (and its children). |
| `advance_day() -> void` | Increments `current_day`; emits `day_changed`. Called by TimeSystem. |
| `set_scene_id(scene_id: String) -> void` | Sets `current_scene_id`; emits `scene_changed`. Called by SceneManager on swap completion. |
| `set_save_slot(slot_name: String) -> void` | Sets `save_slot`; emits `save_slot_changed`. Called on New Game / Load. |
| `create_pathfinding_strategy() -> PathfindingStrategy` | Instantiates a strategy instance corresponding to `pathfinding_strategy`. |
| `set_pathfinding_strategy(new_type: PathfindingStrategyType) -> void` | Sets the global pathfinding strategy, emits `pathfinding_strategy_changed`, and updates live colonists. |
| `get_local_player() -> Node` / `set_local_player(p: Node) -> void` | Accessors for `local_player`. |
| `serialize() -> Dictionary` / `deserialize(data: Dictionary) -> void` | SaveSystem contract — persists `current_day`, `current_scene_id`, `pathfinding_strategy` (run framing only; `save_slot`/`paused`/`map_root` are orchestrator-owned or transient). See [Save / Load](save.md). |

### Class: SceneManager

**Extends:** Node (autoload)  
**Script:** `scene_manager.gd`  
**Description:** Map transition orchestrator and UI screen manager. Owns SQLite stream redirection, map instantiation, entity reparenting between maps, and full-screen screen swapping. `setup()` is called once by `Main._ready` to hand it the node slots (`World`, `UILayer`) it manages. Each map is named by its `MapDef.id` on mount (`Main/World/<map_id>`); the outgoing map is renamed `<id>_unloading` before `queue_free()` so a same-id reload keeps the clean name.  
**Used by:** `Main` (setup, once), `SaveSystem` (current map/player queries, park hooks), `main.gd::_unhandled_input` (screen open/close), any transit trigger (`swap_map`).

**Functions:**

| Function | Description |
|---|---|
| `setup(map_parent: Node, ui_layer: CanvasLayer) -> void` | Called once by `Main._ready`; stores the slots maps/screens mount under. |
| `set_player(player: Player) -> void` / `get_player() -> Player` | Registers/returns the persistent `Player`, reparented into each map by `_wire_map`. |
| `get_current_scene_id() -> String` / `get_current_map() -> Node` | Current map id / root node, or `""` / `null` if none loaded. |
| `swap_map(scene_id: String) -> void` | The single map-load entry point (base startup and POI travel both call this). Emits `map_loading`/`map_unloading`/`map_loaded`; frees the outgoing map; instantiates and wires the new one (see Map Swap Flow). Coroutine — awaits one process frame before wiring so child `_ready` (e.g. `CameraRig`) runs first. |
| `unload_current_map() -> void` | Frees the current map without loading a replacement (Quit-to-Main-Menu). Emits `map_unloading` first so `SaveSystem` can park. |
| `wipe_map_cache() -> void` | Deletes `user://maps/` so the next swaps pull fresh copies from `res://`. Called at New Game start (SaveSystem INV-2). |
| `open_screen(screen_id: String) -> void` / `close_screen() -> void` / `is_screen_open() -> bool` | Full-screen UI slot management on the layer-20 `UILayer`. `open_screen` closes any current screen first (no stacking) and registers the new one with `UiGate`. |

**Internal functions:** `_redirect_sqlite_stream` / `_redirect_terrain_stream` (INV-1 copy-on-load, per terrain stream), `_wire_map` (calls `MapWiring.wire_*`, replays authored furniture unless `SaveSystem.apply_parked_state_if_any` claims the map, reparents + positions the player), `_remove_recursive` (recursive `user://` delete helper, mirrored in `SaveSystem` for slot dirs — see [Save / Load](save.md)).

### Class: TimeSystem

**Extends:** Node (autoload)  
**Script:** `time_system.gd`  
**Description:** Advances the in-game clock in real time. Day length is config-driven (`data/game_config.tres`, `loop_length_minutes`, default 30 real minutes per in-game day). On crossing a day boundary, calls `GameState.advance_day()` (direct) and emits `EventBus.day_rolled_over` (cross-scene relay — SaveSystem autosaves on it, HUD/raids listen). Halts entirely while `GameState.paused`.  
**Used by:** HUD (clock/day display, via polling), `SaveSystem` (autosave hook), raids (night window), Pause Menu (Sleep button calls `advance_to_midnight`).

**Properties:** internal only (`_loop_length_seconds`, `_elapsed_in_day`, `_realtime_play_time`) — read through the functions below, not directly.

**Functions:**

| Function | Description |
|---|---|
| `advance_to_midnight() -> void` | Forces the day boundary immediately (Sleep trigger). |
| `get_time_of_day_fraction() -> float` | `0.0` (dawn) to `~1.0` (just before midnight). |
| `get_elapsed_days() -> float` | Total elapsed in-game days as a decimal (e.g. `2.45`). |
| `get_clock_time() -> Vector2i` | Current in-game `(hour, minute)`, anchored to a dawn offset of 6:00. |
| `get_current_hour() -> int` / `get_current_minute() -> int` | Convenience accessors on `get_clock_time()`. |
| `get_formatted_clock(use_24h: bool = true) -> String` | `"HH:MM"` (24h) or `"HH:MM AM/PM"` (12h). |
| `get_realtime_play_time() -> float` / `get_realtime_play_time_formatted() -> String` | Total unpaused real-time seconds this session, raw or as `"HH:MM:SS"`. |
| `serialize() -> Dictionary` / `deserialize(data: Dictionary) -> void` | SaveSystem contract — persists `elapsed_in_day` and `realtime_play_time` only; `_loop_length_seconds` is config, not run state. |

### Class: Main

**Extends:** Node (`class_name Main`)  
**Script:** `subsystems/core/main.gd` — the project's root scene, persists across the entire session.  
**Description:** Builds the persistent scene skeleton once: `UILayer` (CanvasLayer 20, full-screen UI slot), `HUDLayer` (CanvasLayer 10, HUD slot), `World` (a `Node3D`, the 3D root where SceneManager mounts each map as `World/<map_id>`). Creates the persistent `Player` and hands it to `SceneManager`; mounts the persistent HUD, log feed tail, and dig-box HUD overlay onto `HUDLayer`. Contains no gameplay logic itself — routes global hotkeys and delegates everything else to `SceneManager`/`UiGate`.  
**Used by:** Nothing — it's the scene root. Owns/creates `SceneManager`'s slots, the `Player`, and the persistent HUD-layer widgets.

**Functions:**

| Function | Description |
|---|---|
| `_unhandled_input(event) -> void` | Global hotkey routing: `ui_cancel` (Esc) closes an open screen or opens Pause Menu; `world_map`/`log_history`/`colony_management`/`debug_item_spawn` each toggle their own screen (close if open, else open only when `not UiGate.is_input_blocked()`) — never stack over another open screen. |
