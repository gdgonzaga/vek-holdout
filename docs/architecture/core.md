# Subsystem: Core

The **Core** subsystem (`subsystems/core/`) owns the game's top-level orchestration: main scene composition, autoloads, save/load coordination, time progression, input routing, and the game loop.

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
| `day_changed(new_day)` | `game_state.gd` | *(planned: HUD day counter — not yet connected)* | No (GameState signal) | — |
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

**Signals:**

| Signal | Description |
|---|---|
| `day_changed(new_day: int)` | Midnight crossed. Listeners: HUD day counter. |
| `scene_changed(scene_id: String)` | SceneManager swap completed. Listeners: HUD. |
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

### Class: SceneManager

**Extends:** Node (autoload)  
**Script:** `scene_manager.gd`  
**Description:** Map transition orchestrator and UI screen manager. Owns SQLite stream redirection, map instantiation, entity reparenting between maps, and full-screen screen swapping.
