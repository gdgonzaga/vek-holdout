# Architecture — Vek: Holdout — Overview

> Companion to `GDD.md` (v2.6). Every subsystem below maps to a GDD section; cross-references are in each subsystem's Files table. **Scope:** medium solo project — simple over flexible, no over-engineering.

---

## Directory Structure

```
res://
├── subsystems/         # All logical subsystems (moved here from the project root)
│   ├── autoloads/      # Singleton scripts (GameState, EventBus, SceneManager, SaveSystem,
│   │                   #   Colony, TimeSystem, RunProgress, Tools)
│   ├── core/           # Main scene, shared utilities, global UI shell, save system
│   ├── voxel/          # Voxel world, block grid, terrain (wraps Zylann's voxel_tool)
│   ├── player/         # Player controller, camera rig, state machine
│   ├── build/          # Blueprint mode, BuildLibrary catalog, ghost preview, block placement
│   │                   #   strategies, furniture layer, grid adapters
│   ├── colonists/      # Colonist entities, roster, Job Board, labor AI
│   ├── skills/         # SkillSet component, skill progression, work-speed multipliers
│   ├── combat/         # Damage resolution, weapons, durability, enemy base + archetypes
│   ├── equipment/      # Equipment component, loadout templates, auto-equip/unequip
│   ├── raids/          # Raid scheduler, threat direction, spawn manager
│   ├── expeditions/    # ExpeditionManager: POI discovery, expedition lifecycle
│   ├── maps/           # MapLibrary catalog, MapWiring, SpawnHelpers, map_template.tscn
│   ├── loot/           # Loot tables, container logic, Key Item pool
│   ├── inventory/      # Weight-based inventory, ItemDef, ItemDB
│   ├── crafting/       # Recipe model, station logic, craft-Job flow
│   └── actions/        # Interaction runtime + data: InteractionComponent, GameAction, Condition, ActionOption
├── ui/                 # HUD + all full-screen UIs (kept at project root for now)
│   ├── hud/
│   ├── interaction/    # E-key pop-up menu (InteractionUi)
│   ├── build_menu/
│   ├── player_screen/
│   ├── colony_screen/
│   ├── world_map/
│   ├── pause_menu/
│   ├── main_menu/       # New Game (splash → menu → base_colony)
│   ├── splash/          # Boot splash → auto-advances to Main Menu
│   ├── game_over/
│   ├── day_summary/
│   ├── settings/
│   └── shared/         # Reusable subscenes (health_bar, inventory_slot, roster_row, job_log_entry, memorial_entry)
├── data/               # All .tres/.json data (centralized)
│   ├── characters/     # CharacterDef per type (player, colonist, companion, brawler, shooter)
│   ├── blocks/         # Block definitions (wood/scrap/stone/metal/reinforced)
│   ├── buildables/     # BuildableDef (player-placed objects: pole, etc.)
│   ├── colonists/      # Colonist definitions (ColonistDef)
│   ├── furniture/      # FurnitureDef (dimensions + action_options) — partial (C1)
│   ├── capability_params/ # Capability parameter schemas (CraftingParams, StorageParams, …) — composition-pattern sub-resources for FurnitureDef
│   ├── items/          # Item definitions
│   ├── loot/           # Loot tables (standard.tres, deep.tres) + key_items.tres pool
│   ├── loadouts/       # Loadout templates (player-created + saved per run)
│   ├── recipes/        # Recipe definitions (workbench.tres, forge.tres)
│   ├── skills/         # Skill definitions (6 skills) + use-curves + level multipliers
│   ├── maps/           # One subdirectory per map (<id>/map.sqlite + map_def.tres); see [Maps](maps.md) subsystem
│   ├── game_config.tres    # Engine-level constants
│   ├── energy_config.tres      # Planned — Global Stamina thresholds/floors + Breath rates (Energy subsystem)
│   ├── raid_curve.tres         # Planned — Raid escalation table (Raids subsystem)
│   └── starting_conditions.tres # Planned — Day-1 resources/equipment/structure (§9; C7)
├── addons/             # Editor plugins (dev tooling; not shipped gameplay). voxel_paint: WYSIWYG terrain authoring.
├── debug/              # Debug console (dev/playtest only; stripped from release)
├── tests/              # Automated unit/integration tests (run in CI / headless)
├── testing/            # Manual playtest scenes (developer-run, not shipped)
└── tools/              # Editor/build utilities (EditorScript tools — not shipped)
```

**Placement rules:** subsystem folder = architecture section by default. Ambiguous ownership → `core/`. Autoloads always in `subsystems/autoloads/`. All data in `data/` (centralized, not scattered). Playtest/manual scenes go in `testing/`, automated tests in `tests/`. UI scenes live in `ui/` (project root), not under `subsystems/`. Editor-only tooling (no runtime code) goes in `addons/`; standalone `EditorScript` build/bake utilities go in `tools/`.

### Editor plugins (`addons/`)

Dev-facing editor tooling, not shipped gameplay. Documented here because the map authoring flow depends on it (see `docs/HOWTO-create-a-map.md`).

| Plugin | Purpose |
|---|---|
| `voxel_paint/` | WYSIWYG terrain + furniture painter (`EditorPlugin`). Toolbar button visible for any node selection; LMB paints, Shift+LMB erases, writes via `VoxelTool.do_sphere`, flushes with `save_modified_blocks()`. Each map owns its own `.tscn` stamped from a pristine template (with a per-map `VoxelStreamSQLite`), so furniture markers are isolated per map. The panel's **Maps** section lists existing maps (open to edit) and **+ New Map** creates a new per-map scene + sqlite + catalog entry. Hit detection is a `get_voxel()` ray-march (Godot physics raycast + `VoxelTool.raycast` are dead in the editor viewport — `VoxelTerrain` emits no chunks/collision there; see `docs/VOXEL-TOOL-NOTES.md`). |

## Scene Tree Overview

- **Main** (`main.tscn`) — root scene, persists across entire game session. Owns the scene-transition machinery and the always-on CanvasLayers.
  - CanvasLayer (`layer=10`) — UI overlay layer
    - **HUD** (`hud.tscn`) — persistent in-game overlay (HP/Durability/Stamina/Breath bars, hotbar, build-mode ghost). Instanced by Main at startup; hidden during full-screen menus.
  - CanvasLayer (`layer=20`) — Full-screen UI layer (Player/Colony/World Map/Pause/MainMenu/GameOver/Settings). Only one present at a time; managed by `SceneManager.open_screen` / `close_screen`.
  - **MapRootSlot** (Node) — the mount point for the current map. Swapped by SceneManager on base↔POI transitions.
    - **Map** (`map.tscn` / per-map `data/maps/<id>/map.tscn`, root script `map.gd` — `Map`) — the current game world; a structural container only (no gameplay logic). See [Maps](maps.md) subsystem.
    - VoxelGrid (Node, `voxel_grid.gd`) — the `IBlockGrid` owner; sole voxel_tool access point
      - VoxelTerrain (`voxel_tool` blocky mode). Its `VoxelStreamSQLite` is injected/redirected by SceneManager at load time (runtime copy lives in `user://maps/<id>/`).
    - **Player** (`player.tscn`)
    - ColonistContainer (Node3D) — holds active colonist instances
    - EnemyContainer (Node3D) — holds active enemy instances
    - FurnitureContainer (Node3D) — holds free-standing furniture placed at runtime (Build subsystem)
    - BuildController (`build.tscn`) — active only in Blueprint mode
- **Boot** (`boot.tscn`) — project entry point; loads Main, then opens the Splash → Main Menu. The menu gates gameplay (New Game → `swap_map("base_colony")`).

**Scene transitions:** SceneManager swaps the current `Map` under `MapRootSlot` between the base scene and POI scenes (single entry point: `swap_map(map_id)`). Full-screen UIs replace each other in the `layer=20` CanvasLayer via `open_screen` / `close_screen` (currently: world map, opened with **M**; Esc closes any open screen before toggling pause). The HUD stays mounted throughout gameplay; hidden when any full-screen UI opens (pause/menu) per §12 "full pause everywhere."

## Autoloads / Singletons

Only scripts genuinely needed across multiple unrelated scenes. Solo project — minimal.

| Name | Script | Responsibility |
|---|---|---|
| **GameState** | `game_state.gd` | Run-level state: current day, time-of-day, save slot, pause state, current scene (base vs POI). Emits state-change signals (NOT through EventBus). |
| **EventBus** | `event_bus.gd` | Global signal relay for cross-scene events only (see registry). |
| **GameLog** | `game_log.gd` | Player-facing game log history (capped ring buffer of `LogEntry`). Auto-subscribes to EventBus signals (deaths, day rollover, expeditions, raids, furniture) so the feed is usable out of the box; gameplay code also calls `log()` directly. Emits `entry_added` consumed by the LogFeed HUD tail and LogHistory scrollback. See [Game Log](game-log.md) subsystem. |
| **SceneManager** | `scene_manager.gd` | Load/unload the current Map with transitions; manage the full-screen UI layer; runtime SQLite stream redirect. |
| **SaveSystem** | `save_system.gd` | Autosave on sleep/midnight/quit; load on Continue/New Game. |
| **Colony** | `colony.gd` | The colony roster + Job Board. Cross-scene because base and POI scenes both need it (colonists stay in colony during expeditions). |
| **TimeSystem** | `time_system.gd` | Continuous time advance, day boundary (midnight) event, links to Stamina accrual. Cross-scene because time advances in both base and POI. |
| **RunProgress** | `run_progress.gd` | Run-scoped *earned* state. Currently holds buildable unlocks; **intended to grow into the home for Colony's run-state children** (Memorial, KeyItemPool, LoadoutManager, DiscoveredGear) and other run-earned state — migration ongoing. A "dumb bag" of ids only (no data-def reading). Reset by the New Game orchestrator, then reseeded by `EventBus.run_started`. Saved with the run, wiped on New Game. |
| **BuildLibrary** | `build_library.gd` | The read-only catalog of everything buildable. Loads every `BuildableDef` subclass (`BlockDef`, `BuildableDef`, `FurnitureDef`) from `data/blocks/`, `data/buildables/`, `data/furniture/` into one `id → def` map. "What's unlocked" is delegated to `RunProgress` — this catalog seeds the default-unlocked defs at startup and on `EventBus.run_started`, then exposes `is_unlocked` / `get_unlocked` / `unlock` / `get_def`. Read-only after `_ready`. See [Build](build.md) subsystem. |
| **MapLibrary** | `map_library.gd` | Read-only catalog of all loadable maps. Scans `data/maps/*/map_def.tres` at startup into an `id → MapDef` map. Looked up by `SceneManager.swap_map()` and `ExpeditionManager`. Read-only after `_ready`. See [Maps](maps.md) subsystem. |
| **ExpeditionManager** | `expedition_manager.gd` | Tracks discovered POIs and the on/off-expedition flag. `start_expedition()` / `end_expedition()` emit the EventBus signals and delegate map loading to `SceneManager.swap_map()`. Scaffold — hex-grid + crew logic deferred. See [Expeditions](expeditions.md) subsystem. |
| **ItemDB** | `item_db.gd` | Read-only catalog of item definitions. Scans `data/items/*.tres` at startup; keyed by filename stem. Read-only after `_ready`. `get_def(item_id) -> ItemDef`, `has_def(item_id) -> bool`. See [Inventory](inventory.md) subsystem. |
| **Tools** | `tools.gd` | General cross-subsystem utilities. Currently: `generate_uuid() -> String` (cryptographically random RFC 4122 UUID v4). |

**Deliberately NOT autoloads** (kept as scene-scoped references):
- CharacterInventory — belongs to the player/colonist node; accessed via the entity node.
- Raid scheduler — base-scene only; expeditions don't trigger base raids during the mission (raid resolves on return).
- Threat-direction weights — part of Colony state, but only base scene reads them at raid time.

### EventBus Signal Registry

Authoritative list of `event_bus.gd` signals. Cross-scene only.

| Signal | Emitted by | Listeners | Purpose |
|---|---|---|---|
| `run_started()` | New Game orchestrator | RunProgress seeders (BuildLibrary, etc.), GameLog | New Game reset complete; seeders re-add default unlocks to RunProgress (additive — safe to run repeatedly); GameLog clears history |
| `day_rolled_over(new_day: int)` | `time_system.gd` | `save_system.gd`, HUD, raids scheduler, GameLog | Midnight crossed; triggers autosave + Day Summary prep; GameLog posts a "Day N begins" line |
| `raid_started(raid_data: Dictionary)` | raids subsystem | HUD, Colony (stance assignment), colonists | Begin raid sequence |
| `raid_ended(outcome: Dictionary)` | raids subsystem | HUD, Colony, save_system | Raid resolved; unlock player control |
| `expedition_started(crew: Array, poi_id: String)` | `ExpeditionManager` | Colony, colonists, GameLog (SceneManager swap happens in `start_expedition` itself) | Travel to POI scene |
| `expedition_ended(result: Dictionary)` | `ExpeditionManager` | Colony, HUD, GameLog (SceneManager swap happens in `end_expedition` itself) | Return to base scene |
| `map_loading(map_id: String)` | `SceneManager` (before instantiate) | HUD (loading screen, planned) | Map swap begins |
| `map_loaded(map_id: String)` | `SceneManager` (after wiring) | world map UI, HUD, save_system | Map ready; actors wired, terrain streamed |
| `map_unloading(map_id: String)` | `SceneManager` (before free) | save_system (autosave on leave, planned) | Current map about to be freed |
| `colonist_died(colonist_id: String)` | combat subsystem | Colony, HUD, Memorial, GameLog | Named colonist death; adds to memorial roster |
| `player_died(context: String)` | combat subsystem | GameState, HUD | Player HP hit 0 (respawn handling) |
| `game_over()` | GameState | SceneManager | All colonists + player dead; load Game Over scene |
| `blueprint_mode_toggled(active: bool)` | player subsystem | BuildController, HUD | Mode layer change |
| `buildable_selected(id: String)` | player subsystem | BuildController | Player selected a buildable in the build menu (sets the controller's `selected_id`) |
| `furniture_placed(def_id: String, anchor: Vector3i)` | FurnitureLayer | Colony (Functional Rooms), GameLog | Furniture placed in world — increments the relevant Functional Rooms counter; GameLog posts a "Built <def_id>" line |
| `furniture_removed(def_id: String, anchor: Vector3i)` | FurnitureLayer | Colony (Functional Rooms), GameLog | Furniture removed from world — decrements the relevant Functional Rooms counter; GameLog posts a "Removed <def_id>" line |
| `item_picked_up(item_id: String, count: int)` | inventory subsystem | HUD (hotbar/inventory refresh) | Inventory changed while Player screen closed |
| `job_logged(entry: Dictionary)` | colonists (Job Board) | UI (Job Log panel, when open) | Diagnostic feed for job failures |

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
- **Colonist/job state → Colony (autoload).** The roster and Job Board live on Colony; UI reads/writes via Colony's public methods. Colony emits its own signals for roster changes.
- **Signals describe events, not commands.** `colonist_died`, not `kill_colonist`.

## Key Conventions

- Every script, scene, and data file must belong to a documented subsystem. Ambiguous → `core/`.
- All data (block stats, enemy stats, loot tables, raid curves, armor Durability values, item defs) lives in `res://data/` as `.tres` Resource files. No hardcoded content values in scripts.
- Voxel-specific code is isolated to `voxel/`. No other subsystem imports `voxel_tool` directly — they go through `voxel/`'s interfaces (see [Build](build.md) subsystem's grid adapter).
- All enemies extend `enemy_base.gd` — never build an enemy from scratch.
- All colonists extend `colonist_base.gd`.
- **UI elements are `.tscn` scenes**, not built dynamically in code. Reusable subscenes (health bar, inventory slot, hotbar cell, colonist roster row, job-log entry) are standalone scenes instanced where needed. Modifying scene-instanced UI props in code is fine; creating the element in code is not.
- Scene-specific UI lives inside its own scene. Only HUD is global/persistent.
- No `get_node("../../")` path hacks — use signals or autoloads for cross-scene access.
- Scripts in one subsystem folder must not `preload` or use direct node paths into another subsystem's folder. Cross-subsystem = autoloads or EventBus.
- `class_name` is global — if two scripts in different subsystems would collide, prefix with subsystem (`PlayerHUD` vs `ColonyHUD`). Only prefix on actual collision risk.
- **Naming:** PascalCase for nodes/classes (`Player`, `JobBoard`, `Brawler`); snake_case for files (`player.gd`, `job_board.gd`, `main.tscn`); `.tscn` matches root node name.
- **Prototype art:** capsule primitives (`CapsuleMesh`) for all characters/enemies until art pass. No model sourcing during prototype phase.
- **Pause semantics:** full pause everywhere (raids included). `pause_state_changed` toggles `process_mode = PROCESS_MODE_DISABLED` on simulation nodes. UI keeps `PROCESS_MODE_ALWAYS`.
