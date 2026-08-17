# Architecture — Vek: Holdout — Overview

> Companion to `GDD.md` (v2.6). Every subsystem below maps to a GDD section; cross-references are in each subsystem's Files table. **Scope:** medium solo project — simple over flexible, no over-engineering.

---

## Directory Structure

```
res://
├── subsystems/         # All logical subsystems (moved here from the project root)
│   ├── autoloads/      # Singleton scripts (GameState, EventBus, UiGate, GameLog, SceneManager,
│   │                   #   SaveSystem, Colony, TimeSystem, RunProgress, Tools)
│   ├── core/           # Main scene, shared utilities, global UI shell, save system
│   ├── voxel/          # Voxel world, block grid, terrain (wraps Zylann's voxel_tool)
│   ├── player/         # Player controller, camera rig, state machine
│   ├── build/          # Blueprint mode, BuildLibrary catalog, ghost preview, block placement
│   │                   #   strategies, furniture layer, grid adapters
│   ├── furniture/      # Furniture runtime node (placed-item instance; back-ref to its def)
│   ├── colonists/      # Colonist entity, AI loop, Job/JobBoard, voxel A* pathfinder, components
│   │                   #   (SkillSet lives here too — the skills/ folder below is an empty placeholder)
│   ├── skills/         # Empty placeholder — SkillSet/skill progression live in colonists/
│   ├── combat/         # Planned — damage resolution, weapons, durability, enemy base + archetypes (empty)
│   ├── equipment/      # Planned — equipment component, loadout templates (empty)
│   ├── raids/          # Planned — raid scheduler, threat direction, spawn manager (empty)
│   ├── expeditions/    # ExpeditionManager: POI discovery, expedition lifecycle
│   ├── maps/           # MapLibrary catalog, MapWiring, SpawnHelpers, map_template.tscn
│   ├── loot/           # Planned — loot tables, container logic, Key Item pool (empty)
│   ├── inventory/      # Weight-based inventory, ItemDef, ItemDB
│   ├── crafting/       # Recipe model, station logic, craft-Job flow
│   ├── farming/        # Growable component, CropLibrary — crop lifecycle on farm-plot furniture
│   ├── harvesting/     # Harvestable component — work-time + yield resolution for marked resources
│   └── actions/        # Interaction runtime + data: InteractionComponent, GameAction, Condition, ActionOption
├── ui/                 # HUD + all full-screen UIs (kept at project root for now)
│   ├── hud/
│   ├── interaction/    # E-key pop-up menu (InteractionUi)
│   ├── log_feed/       # Game log: persistent HUD tail
│   ├── log_history/    # Game log: full-screen scrollback (H)
│   ├── build_menu/
│   ├── storage/        # Player↔container transfer panel
│   ├── player_screen/
│   ├── colony_screen/
│   ├── world_map/
│   ├── pause_menu/
│   ├── main_menu/       # New Game + Load Game (splash → menu → base)
│   ├── load_menu/        # Load Game screen (save-slot list)
│   ├── splash/          # Boot splash → auto-advances to Main Menu
│   ├── game_over/
│   ├── day_summary/
│   ├── settings/
│   ├── crafting/        # Crafting station panel (open_crafting action)
│   ├── crop_inspect/    # Farm plot inspector (crop status/neglect)
│   ├── crop_picker/     # Crop selection dialog for empty farm plots
│   ├── action_progress/ # Radial work gauge shown while a manual action charges
│   ├── colony_management/ # Full-screen colony overview (Tab): roster, labor, stations, storage
│   └── shared/         # Reusable subscenes (health_bar, inventory_slot, roster_row, job_log_entry, memorial_entry)
├── data/               # All .tres/.json data (centralized)
│   ├── characters/     # Planned — CharacterDef per type (empty today)
│   ├── blocks/         # Block definitions (wood/scrap/stone/metal/reinforced)
│   ├── buildables/     # BuildableDef (player-placed objects: pole, etc.)
│   ├── colonists/      # Colonist definitions (ColonistDef)
│   ├── furniture/      # FurnitureDef (dimensions + action_options) — partial (C1)
│   ├── capability_params/ # Capability parameter schemas (CraftingParams, StorageParams, …) — composition-pattern sub-resources for FurnitureDef
│   ├── items/          # Item definitions
│   ├── loot/           # Planned — loot tables + key_items pool (empty today)
│   ├── loadouts/       # Planned — loadout templates (empty today)
│   ├── recipes/        # Recipe definitions (axe.tres, planks.tres; wooden_board.tres lives in crafting/)
│   ├── skills/         # Skill definitions (7 skills) + use-curves + level multipliers
│   ├── maps/           # One subdirectory per map (<id>/map.sqlite + map_def.tres + stamped map.tscn); see [Maps](maps.md) subsystem
│   ├── game_config.tres    # Engine-level constants
│   ├── energy_config.tres      # Planned — Global Stamina thresholds/floors + Breath rates (Energy subsystem)
│   ├── raid_curve.tres         # Planned — Raid escalation table (Raids subsystem)
│   └── starting_conditions.tres # Planned — Day-1 resources/equipment/structure (§9; C7)
├── addons/             # Editor plugins (dev tooling; not shipped gameplay). voxel_paint: WYSIWYG terrain authoring.
├── debug/              # Vestigial placeholder (planned debug console) — don't write here
├── test/               # gdUnit4 test suites (run in CI / headless)
├── tests/              # Vestigial placeholder — don't write here (real suites live in test/)
├── testing/            # Manual playtest scenes (developer-run, not shipped)
└── tools/              # Editor/build utilities (EditorScript tools — not shipped)
```

**Placement rules:** subsystem folder = architecture section by default. Ambiguous ownership → `core/`. Autoloads always in `subsystems/autoloads/`. All data in `data/` (centralized, not scattered). Playtest/manual scenes go in `testing/`, automated tests in `test/`. UI scenes live in `ui/` (project root), not under `subsystems/`. Editor-only tooling (no runtime code) goes in `addons/`; standalone `EditorScript` build/bake utilities go in `tools/`.

### Editor plugins (`addons/`)

Dev-facing editor tooling, not shipped gameplay. Documented here because the map authoring flow depends on it (see `docs/HOWTO-create-a-map.md`).

| Plugin | Purpose |
|---|---|
| `voxel_paint/` | WYSIWYG terrain + furniture painter (`EditorPlugin`). Toolbar button visible for any node selection; LMB paints, Shift+LMB erases, writes via `VoxelTool.do_sphere`, flushes with `save_modified_blocks()`. Each map owns its own `.tscn` stamped from a pristine template (with a per-map `VoxelStreamSQLite`), so furniture markers are isolated per map. The panel's **Maps** section lists existing maps (open to edit) and **+ New Map** creates a new per-map scene + sqlite + catalog entry. Hit detection is a `get_voxel()` ray-march (Godot physics raycast + `VoxelTool.raycast` are dead in the editor viewport — `VoxelTerrain` emits no chunks/collision there; see `docs/VOXEL-TOOL-NOTES.md`). |

## Scene Tree Overview

- **Main** (`main.tscn`) — root scene, persists across entire game session. Owns the scene-transition machinery and the always-on CanvasLayers.
  - CanvasLayer (`layer=10`) — UI overlay layer
    - **HUD** (`hud.tscn`) — persistent in-game overlay (crosshair, instructions label, interact prompt, inventory panel). Instanced by Main at startup; hidden during full-screen menus.
  - CanvasLayer (`layer=20`) — Full-screen UI layer (WorldMap/LogHistory/ColonyManagement/MainMenu/LoadMenu/GameOver/Settings). Only one present at a time; managed by `SceneManager.open_screen` / `close_screen`. (The **Pause overlay** is the exception — it mounts its own **layer-30** `CanvasLayer` so it always renders above the layer-20 UI and the layer-10 HUD.)
  - **MapRootSlot** (Node) — the mount point for the current map. Swapped by SceneManager on base↔POI transitions.
    - **Map** (`map.tscn` / per-map `data/maps/<id>/map.tscn`, root script `map.gd` — `Map`) — the current game world; a structural container only (no gameplay logic). See [Maps](maps.md) subsystem.
    - VoxelGrid (Node, `voxel_grid.gd`) — the `IBlockGrid` owner; sole voxel_tool access point
      - VoxelTerrain (`voxel_tool` blocky mode). Its `VoxelStreamSQLite` is injected/redirected by SceneManager at load time (runtime copy lives in `user://maps/<id>/`).
    - **Player** (`player.tscn`)
    - ColonistContainer (Node3D) — holds active colonist instances
    - EnemyContainer (Node3D) — holds active enemy instances
    - FurnitureContainer (Node3D) — holds free-standing furniture placed at runtime (Build subsystem)
    - BuildController (`build.tscn`) — active only in Blueprint mode
- **Boot** (`boot.tscn`) — project entry point; loads Main, then opens the Splash → Main Menu. The menu gates gameplay (New Game → `swap_map("base")`).

**Scene transitions:** SceneManager swaps the current `Map` under `MapRootSlot` between the base scene and POI scenes (single entry point: `swap_map(map_id)`). Full-screen UIs replace each other in the `layer=20` CanvasLayer via `open_screen` / `close_screen` (currently: world map (**M**), log history (**H**), colony management (**Tab**); Esc closes any open screen before toggling pause). The HUD stays mounted throughout gameplay; hidden when any full-screen UI opens (pause/menu) per §12 "full pause everywhere."

## Autoloads / Singletons

Only scripts genuinely needed across multiple unrelated scenes. Solo project — minimal.

| Name | Script | Responsibility |
|---|---|---|
| **GameState** | `game_state.gd` | Run-level state: current day, time-of-day, save slot, pause state, current scene (base vs POI). Emits state-change signals (NOT through EventBus). |
| **EventBus** | `event_bus.gd` | Global signal relay for cross-scene events only (see registry). |
| **UiGate** | `ui_gate.gd` | Single source of truth for "a modal UI is open" and sole owner of the cursor outside gameplay — blocks input leakage through open screens and prevents modal stacking. See [UI](ui.md). |
| **GameLog** | `game_log.gd` | Player-facing game log history (capped ring buffer of `LogEntry`). Auto-subscribes to EventBus signals (deaths, day rollover, expeditions, raids, furniture) so the feed is usable out of the box; gameplay code also calls `log()` directly. Emits `entry_added` consumed by the LogFeed HUD tail and LogHistory scrollback. See [Game Log](game-log.md) subsystem. |
| **SceneManager** | `scene_manager.gd` | Load/unload the current Map with transitions; manage the full-screen UI layer; runtime SQLite stream redirect. |
| **SaveSystem** | `save_system.gd` | Multi-slot save/load orchestrator. Autosave at midnight (`day_rolled_over` hook); manual save via the pause menu; parks the live map on map swap (`map_unloading` hook). See [Save / Load](save.md). |
| **Colony** | `colony.gd` | The colony roster + Job Board (construction Jobs produced from `EventBus.blueprint_placed`). Cross-scene — colonists persist base↔POI (reparented into the current map's `ColonistContainer` on each swap). See [Colonists](colonists.md). |
| **TimeSystem** | `time_system.gd` | Continuous time advance; emits `day_rolled_over` at the midnight boundary. Cross-scene because time advances in both base and POI. |
| **RunProgress** | `run_progress.gd` | Run-scoped *earned* state. Currently holds buildable unlocks; **intended to grow into the home for Colony's run-state children** (Memorial, KeyItemPool, LoadoutManager, DiscoveredGear) and other run-earned state — migration ongoing. A "dumb bag" of ids only (no data-def reading). Reset by the New Game orchestrator, then reseeded by `EventBus.run_started`. Saved with the run, wiped on New Game. |
| **BuildLibrary** | `build_library.gd` | The read-only catalog of everything buildable. Loads every `BuildableDef` subclass (`BlockDef`, `BuildableDef`, `FurnitureDef`) from `data/blocks/`, `data/buildables/`, `data/furniture/` into one `id → def` map. "What's unlocked" is delegated to `RunProgress` — this catalog seeds the default-unlocked defs at startup and on `EventBus.run_started`, then exposes `is_unlocked` / `get_unlocked` / `unlock` / `get_def`. Read-only after `_ready`. See [Build](build.md) subsystem. |
| **Tools** | `tools.gd` | General cross-subsystem utilities. Currently: `generate_uuid() -> String` (cryptographically random RFC 4122 UUID v4). |
| **MapLibrary** | `map_library.gd` | Read-only catalog of all loadable maps. Scans `data/maps/*/map_def.tres` at startup into an `id → MapDef` map. Looked up by `SceneManager.swap_map()` and `ExpeditionManager`. Read-only after `_ready`. See [Maps](maps.md) subsystem. |
| **ItemDB** | `item_db.gd` | Read-only catalog of item definitions. Scans `data/items/*.tres` at startup; keyed by `ItemDef.id`. Read-only after `_ready`. `get_def(item_id) -> ItemDef`, `has_def(item_id) -> bool`. See [Inventory](inventory.md) subsystem. |
| **ExpeditionManager** | `expedition_manager.gd` | Tracks discovered POIs and the on/off-expedition flag. `start_expedition()` / `end_expedition()` emit the EventBus signals and delegate map loading to `SceneManager.swap_map()`. Scaffold — hex-grid + crew logic deferred. See [Expeditions](expeditions.md) subsystem. |

**Deliberately NOT autoloads** (kept as scene-scoped references):
- CharacterInventory — belongs to the player/colonist node; accessed via the entity node.
- Raid scheduler — base-scene only; expeditions don't trigger base raids during the mission (raid resolves on return).
- Threat-direction weights — part of Colony state, but only base scene reads them at raid time.

### EventBus Signal Registry

Authoritative list of `event_bus.gd` signals. Cross-scene only.

| Signal | Emitted by | Listeners | Purpose |
|---|---|---|---|
| `run_started()` | New Game orchestrator | RunProgress seeders (BuildLibrary, etc.), GameLog | New Game reset complete; seeders re-add default unlocks to RunProgress (additive — safe to run repeatedly); GameLog clears history |
| `day_rolled_over(new_day: int)` | `time_system.gd` | `save_system.gd`, GameLog | Midnight crossed; triggers autosave; GameLog posts a "Day N begins" line |
| `raid_started(raid_data: Dictionary)` | — declared, no emitter yet (raids unbuilt) | GameLog | Begin raid sequence |
| `raid_ended(outcome: Dictionary)` | — declared, no emitter yet (raids unbuilt) | GameLog | Raid resolved; unlock player control |
| `expedition_started(crew: Array, poi_id: String)` | `ExpeditionManager` | Colony, colonists, GameLog (SceneManager swap happens in `start_expedition` itself) | Travel to POI scene |
| `expedition_ended(result: Dictionary)` | `ExpeditionManager` | Colony, HUD, GameLog (SceneManager swap happens in `end_expedition` itself) | Return to base scene |
| `map_loading(map_id: String)` | `SceneManager` (before instantiate) | — none yet (loading screen planned) | Map swap begins |
| `map_loaded(map_id: String)` | `SceneManager` (after wiring) | world map UI | Map ready; actors wired, terrain streamed |
| `map_unloading(map_id: String)` | `SceneManager` (before free) | save_system (parks the live map) | Current map about to be freed |
| `colonist_died(colonist_id: String)` | `colonist.gd` | GameLog | Named colonist death |
| `player_died(context: String)` | — declared, no emitter yet (combat unbuilt) | GameState, HUD (planned) | Player HP hit 0 (respawn handling) |
| `game_over()` | — declared, no emitter yet | SceneManager (planned) | All colonists + player dead; load Game Over scene |
| `build_placement_toggled(active: bool)` | `player.gd` | BuildController, HUD | Mode layer change |
| `build_menu_toggled(open: bool)` | `player.gd` | `InstructionsLabel` | Build menu visibility — drives the `InstructionsLabel` text for the menu state |
| `buildable_selected(id: String)` | `build_menu.gd` (UI) | `player.gd` (sets the controller's `selected_id`) | Player selected a buildable in the build menu |
| `furniture_placed(def_id: String, anchor: Vector3i)` | FurnitureLayer | GameLog | Furniture placed in world — GameLog posts a "Built <def_id>" line |
| `furniture_removed(def_id: String, anchor: Vector3i)` | FurnitureLayer | Colony, GameLog | Furniture removed from world — GameLog posts a "Removed <def_id>" line |
| `blueprint_placed(target_def_id: String, anchor: Vector3i, blueprint: Node)` | `BlueprintLayer` | Colony (registers a construction Job) | A blueprint (construction plan) was spawned — Colony's JobBoard connects here to create a construction Job a colonist then walks to |
| `blueprint_removed(target_def_id: String, anchor: Vector3i)` | `BlueprintLayer` | Colony (cancels the construction Job) | A blueprint was removed (built or cancelled) — Colony's JobBoard drops any Job targeting that anchor |
| `blueprint_materials_ready(target_def_id: String, anchor: Vector3i, blueprint: Node)` | `Blueprint.deposit_from` | Colony (spawns the construction Job; single-fire per blueprint) | All materials for a blueprint are on site |
| `crafting_order_queued(station: Node, anchor: Vector3i)` | `CraftingStation.queue_recipe` | Colony (spawns the haul Job feeding the station) | A recipe was queued at a station needing materials |
| `crafting_materials_ready(station: Node, anchor: Vector3i)` | `CraftingStation.deposit_from` | Colony (spawns the craft Job; single-fire per order) | All materials for a queued order are in the station |
| `harvest_mark_toggled(furniture: Node, anchor: Vector3i, is_marked: bool)` | `Harvestable.toggle_mark` | Colony | Toggles harvest mark on resources/crops |
| `plot_needs_sowing(growable: Node, anchor: Vector3i, crop_id: String, needed: bool)` | `Growable` | Colony | Spawns or removes sow job for empty farm plots |
| `plot_needs_water(growable: Node, anchor: Vector3i, needed: bool)` | `Growable` | Colony | Spawns or removes water job for thirsty crops |
| `plot_needs_tending(growable: Node, anchor: Vector3i, needed: bool)` | `Growable` | Colony | Spawns or removes tend job for crops needing maintenance |
| `item_picked_up(item_id: String, count: int)` | — declared, no emitter yet | HUD (hotbar/inventory refresh, planned) | Inventory changed while Player screen closed |
| `job_logged(entry: Dictionary)` | colonists (JobBoard) | — none yet (Job Log panel planned) | Diagnostic feed for job failures |

### State-Change Signals (on GameState)

Emitted by GameState when its own state changes. Connect directly — NOT through EventBus.

| Signal | Trigger | Example Listener |
|---|---|---|
| `day_changed(new_day: int)` | Midnight crossing | HUD (day counter) |
| `scene_changed(scene_id: String)` | SceneManager completes swap | HUD (show/hide build controls) |
| `pause_state_changed(paused: bool)` | Pause menu toggled | All simulation nodes (`process_mode` toggle) |
| `save_slot_changed(slot_name: String)` | New Game / Load | SaveSystem |

## Signal Flow Rules

- **Same scene → direct references.** `@onready`, passed references, or parent methods. Player↔BuildController, Player↔Inventory, HUD↔its children all use direct refs.
- **Cross-scene → EventBus.** Anything that must cross a map swap (base↔POI) or reach a CanvasLayer from the world goes through EventBus.
- **GameState changes → GameState signals.** `day_changed`, `pause_state_changed` etc. are emitted by GameState and connected directly. Do NOT relay these through EventBus.
- **Colonist/job state → Colony (autoload).** The roster and Job Board live on Colony; UI reads/writes via Colony's public methods. (Colony currently declares no signals of its own — UI polls its public methods; roster-change signals are a future addition.)
- **Signals describe events, not commands.** `colonist_died`, not `kill_colonist`.

## Key Conventions

- Every script, scene, and data file must belong to a documented subsystem. Ambiguous → `core/`.
- All data (block stats, enemy stats, loot tables, raid curves, armor Durability values, item defs) lives in `res://data/` as `.tres` Resource files. No hardcoded content values in scripts.
- Voxel-specific code is isolated to `voxel/`. No other subsystem imports `voxel_tool` directly — they go through `voxel/`'s interfaces (see [Build](build.md) subsystem's grid adapter).
- All enemies extend `enemy_base.gd` — never build an enemy from scratch.
- All colonists extend `colonist.gd` (`class Colonist`).
- **UI elements are `.tscn` scenes**, not built dynamically in code. Reusable subscenes (health bar, inventory slot, hotbar cell, colonist roster row, job-log entry) are standalone scenes instanced where needed. Modifying scene-instanced UI props in code is fine; creating the element in code is not.
- Scene-specific UI lives inside its own scene. Only HUD is global/persistent.
- No `get_node("../../")` path hacks — use signals or autoloads for cross-scene access.
- Scripts in one subsystem folder must not `preload` or use direct node paths into another subsystem's folder. Cross-subsystem = autoloads or EventBus.
- `class_name` is global — if two scripts in different subsystems would collide, prefix with subsystem (`PlayerHUD` vs `ColonyHUD`). Only prefix on actual collision risk.
- **Naming:** PascalCase for nodes/classes (`Player`, `JobBoard`, `Brawler`); snake_case for files (`player.gd`, `job_board.gd`, `main.tscn`); `.tscn` matches root node name.
- **Prototype art:** capsule primitives (`CapsuleMesh`) for all characters/enemies until art pass. No model sourcing during prototype phase.
- **Pause semantics:** full pause everywhere (raids included). `pause_state_changed` toggles `process_mode = PROCESS_MODE_DISABLED` on simulation nodes. UI keeps `PROCESS_MODE_ALWAYS`.
