# Architecture — Xeno Frontier: Colony Defense — Overview

> Companion to `GDD.md` (v2.7). Every subsystem below maps to a GDD section; cross-references are in each subsystem's Files table. **Scope:** medium solo project — simple over flexible, no over-engineering.

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
│   ├── furniture/      # Furniture runtime node (placed-item instance)
│   ├── colonists/      # Colonist entity, animation controller, voxel pathfinder, roster,
│   │                   #   HungerComponent, SkillSet (skill progression lives here, not a
│   │                   #   standalone skills/ folder)
│   ├── ai/             # AI Subsystem: LimboAI integration, ColonistBrain, ColonistNeeds, BT tasks
│   ├── jobs/           # Fractional job system: JobInstance, WorkerClaim
│   ├── combat/         # In-progress — HealthComponent, EnemyBase, turret defenses, enemy BT tasks
│   ├── equipment/      # Implemented — Equipment component, EquipmentVisualizer, EquipmentAudit
│   ├── raids/          # NightRaidController, radial enemy spawning around player, pacing curves
│   ├── expeditions/    # ExpeditionManager: POI discovery, expedition lifecycle
│   ├── maps/           # MapLibrary catalog, MapWiring, SpawnHelpers
│   ├── map_authoring/  # Map-editor support: vox parsing, structure stamping, tree scattering
│   ├── inventory/      # Weight-based inventory, ItemDef, ItemDB
│   ├── crafting/       # Recipe model, station logic, craft-Job flow
│   ├── farming/        # Growable component, CropLibrary — crop lifecycle
│   ├── harvesting/     # Harvestable component — work-time + yield resolution
│   ├── environment/    # WildFlora runtime entity, plant spawner, vegetation lifecycle
│   ├── mining/         # Dig box designation controller, 3D preview, markers
│   ├── areas/          # Player-designated rectangular regions: Area data model, AreaManager, designation controller
│   └── actions/        # Interaction runtime + data: InteractionComponent, GameAction
├── ui/                 # HUD + all full-screen UIs
│   ├── hud/
│   ├── inventory/
│   ├── interaction/
│   ├── log_feed/
│   ├── log_history/
│   ├── build_menu/
│   ├── storage/
│   ├── storage_filter/
│   ├── player_screen/
│   ├── colony_screen/
│   ├── world_map/
│   ├── pause_menu/
│   ├── main_menu/
│   ├── load_menu/
│   ├── splash/
│   ├── game_over/
│   ├── day_summary/
│   ├── settings/
│   ├── crafting/
│   ├── crop_inspect/
│   ├── crop_picker/
│   ├── action_progress/
│   ├── colony_management/
│   └── shared/
├── data/               # Centralized .tres/.json data
│   ├── ai/             # Behavior tree resources (colonist_root, bt_generic_work, etc.)
│   ├── needs/          # NeedDef resources (need_hunger, need_rest, need_recreation)
│   ├── jobs/           # JobDef resources (construction_job_def, hauling_job_def)
│   ├── blocks/
│   ├── buildables/
│   ├── furniture/
│   ├── crops/
│   ├── maps/
│   └── game_config.tres
├── addons/             # Editor plugins (limboai, voxel_paint, gdUnit4)
├── test/               # gdUnit4 test suites
├── testing/            # Manual playtest scenes
└── tools/              # Editor/build utilities
```

`subsystems/loot/` holds only `LootRoller` so far — enemy drops are built, container loot is still design-only (see [Loot](loot.md)). Functional Rooms
has no dedicated folder either; its planned state is meant to live on the `Colony` autoload (see
[Functional Rooms](functional-rooms.md)).

---

## Subsystems Overview

| Subsystem | Folder | Description |
|---|---|---|
| Core | `subsystems/core/` | Root scene, Main orchestrator, time, save management. |
| Voxel / World | `subsystems/voxel/` | Dual voxel engine wrappers (`BlockyGrid`, `SmoothGrid`). |
| Player | `subsystems/player/` | Character controller, camera rig, interaction input. |
| Build | `subsystems/build/` | Blueprint placement, catalog library, ghost previews. |
| Actions & Interaction | `subsystems/actions/` | E-key menu options, conditions, interaction component. |
| Functional Rooms | `subsystems/core/` (planned) | Room capability tracking based on placed furniture — spec only, see [Functional Rooms](functional-rooms.md). |
| Colonists | `subsystems/colonists/` | Colonist entities, animation controller, pathfinding, squad and tactical deployment. |
| Jobs | `subsystems/jobs/` | Job registry, `JobInstance`, `WorkerClaim` fractional reservations. |
| AI & Behavior Trees | `subsystems/ai/` | LimboAI engine, `ColonistBrain` Utility AI, `ColonistNeeds`, BT tasks. |
| Pathfinding & Navigation | `subsystems/colonists/` | Voxel A* 3D pathfinder (`VoxelPathfinder`). |
| Skills | `subsystems/colonists/` | Entity L1-L5 skill progression and work multipliers. |
| Maps | `subsystems/maps/`, `subsystems/map_authoring/` | Map loading, per-map scenes, wiring helpers, map-editor stamping tools. |
| Expeditions | `subsystems/expeditions/` | POI discovery, expedition departure and return lifecycle. |
| Inventory | `subsystems/inventory/` | Weight-based inventory, items, carrying capacity. |
| Crafting | `subsystems/crafting/` | Workbench/Forge station recipes and craft jobs. |
| Farming | `subsystems/farming/` | Farm plot growables, hydration, crop lifecycle. |
| Harvesting | `subsystems/harvesting/` | Harvestable component, dynamic yield resolution, HarvestBoxController area marking. |
| Wild Flora | `subsystems/environment/` | Wild flora lifecycle, perennial foraging, real-time felling, and tree scattering. |
| Hunger | `subsystems/colonists/` | Physiological satiety tracking, FoodParams, starvation, and LimboAI feeding. |
| Recreation | `subsystems/furniture/` | RecreationParams capability, occupancy slot rationing, recreation need satisfaction. |
| Mining | `subsystems/mining/` | Dig box designation, strata materials, designation markers. |
| Areas | `subsystems/areas/` | Player-designated rectangular regions, CRUD, membership, persistence. |
| Combat | `subsystems/combat/` | HealthComponent, EnemyBase, turret defenses, hostile behavior trees. |
| Equipment | `subsystems/equipment/` | 8-slot gear component, EquipmentVisualizer, EquipmentAudit fulfillment. |
| Raids | `subsystems/raids/` | NightRaidController, radial enemy spawning, spawn-rate pacing curves. |
| Loot | `subsystems/loot/`, `data/loot/` | `LootRoller` and the `LootTable` / `LootEntry` schemas; enemy drops are built, container rolls for scavenge missions are still spec only, see [Loot](loot.md). |
| UI | `ui/` | persistent HUD, full-screen screens, dialogs. |
| Game Log | `subsystems/core/` | On-screen event feed and history log. |

---

## Autoloads / Singletons

| Name | Script | Responsibility |
|---|---|---|
| **GameState** | `game_state.gd` | Run-level state: day, time, save slot, pause state. |
| **EventBus** | `event_bus.gd` | Global signal relay for cross-scene communication. |
| **UiGate** | `ui_gate.gd` | Single source of truth for modal UI state and cursor capture. |
| **GameLog** | `game_log.gd` | Message feed buffer and history log. |
| **SceneManager** | `scene_manager.gd` | Map swapping and screen layer transitions. |
| **SaveSystem** | `save_system.gd` | Multi-slot save/load orchestrator. |
| **Colony** | `colony.gd` | Colony roster, JobBoard, and AreaManager singleton owner. |
| **TimeSystem** | `time_system.gd` | Continuous time advance and day rollover signals. |
| **RunProgress** | `run_progress.gd` | Run-scoped unlocked content tracking. |
| **BuildLibrary** | `subsystems/build/build_library.gd` | Buildable catalog index. |
| **Tools** | `subsystems/autoloads/tools.gd` | Cross-subsystem utility helpers (e.g. UUID generation). |
| **MapLibrary** | `subsystems/maps/map_library.gd` | `id → MapDef` map catalog registry. |
| **ItemDB** | `subsystems/inventory/item_db.gd` | `id → ItemDef` item catalog registry. |
| **EnemyLibrary** | `subsystems/combat/enemy_library.gd` | `id → EnemyDef` enemy archetype catalog registry. |
| **ExpeditionManager** | `subsystems/expeditions/expedition_manager.gd` | POI discovery and expedition lifecycle. |

Order above matches `project.godot`'s `[autoload]` section — later autoloads may depend on earlier ones being ready.

---

## EventBus Signal Registry

Authoritative list of `event_bus.gd` signals. Used exclusively for cross-scene communication (no state).

| Signal | Emitted by | Listeners | Description |
|---|---|---|---|
| `run_started()` | `main_menu.gd` | `BuildLibrary`, `ExpeditionManager`, `GameLog`, `RunProgress` | New Game flow triggered; catalogs re-seed defaults into `RunProgress`. |
| `day_rolled_over(new_day: int)` | `TimeSystem` | `SaveSystem`, `HUD`, `NightRaidController`, `PlantSpawner` | Midnight crossed; triggers autosave, updates HUD day counter, advances raid pacing. |
| `raid_started(raid_data: Dictionary)` | `NightRaidController` | `HUD`, `Colony`, `colonists`, `GameLog` | Nocturnal raid begins; logs event, notifies HUD and colonist combat stances. |
| `raid_ended(outcome: Dictionary)` | `NightRaidController` | `HUD`, `Colony`, `SaveSystem`, `GameLog` | Nocturnal raid concludes at dawn. |
| `expedition_started(crew: Array, poi_id: String)` | `ExpeditionManager` | `SceneManager`, `Colony`, `colonists`, `GameLog` | Expedition departs for designated POI map. |
| `expedition_ended(result: Dictionary)` | `ExpeditionManager` | `SceneManager`, `Colony`, `HUD`, `GameLog` | Expedition completes and returns to colony base. |
| `map_loading(map_id: String)` | `SceneManager` | `HUD` | Map scene loading starts; displays loading screen. |
| `map_loaded(map_id: String)` | `SceneManager` | all subsystems | Map instantiation and wiring completed; triggers world-map repopulation. |
| `map_unloading(map_id: String)` | `SceneManager` | `SaveSystem`, `Colony` | Map scene unloading begins; triggers state parking and stream flushes. |
| `colonist_died(colonist_id: String)` | `Colonist` | `Colony`, `HUD`, `Memorial`, `GameLog` | Colonist dies; logs event and appends to memorial roster. |
| `player_died(context: String)` | `Player` | `GameState`, `HUD` | Player health depleted; triggers death handling and HUD feedback. |
| `game_over()` | `GameState` | `SceneManager`, `HUD` | All colonists and player dead; triggers game over sequence. |
| `build_placement_toggled(active: bool)` | `Player` | `BuildController`, `HUD`, `InstructionsLabel` | Player enters or exits 3D blueprint placement mode. |
| `dig_box_toggled(active: bool)` | `Player` | `DigBoxController`, `HUD` | Player toggles dig box designation mode (**Shift+G**). |
| `dig_box_dimensions_changed(width: int, height: int, depth: int)` | `DigBoxController` | `DigBoxHud` | Live dimensions of active dig box change. |
| `dig_box_mode_changed(mode_name: String)` | `DigBoxController` | `DigBoxHud` | Dig box mode toggles (Horizontal, Vertical, Stairway). |
| `dig_box_designated(voxels: Array)` | `DigBoxController` | `Colony`, `MiningSystem` | Player commits a designated dig box volume. |
| `dig_job_completed(cell: Vector3i)` | `DigJobDef` | `MiningSystem` | Colonist finishes mining a designated voxel. |
| `area_designation_toggled(active: bool)` | `Player` | `AreaDesignationController`, `AreaDesignationHud` | Player enters or exits 3D area designation mode. |
| `area_designation_stage_changed(stage_name: String)` | `AreaDesignationController` | `AreaDesignationHud` | Area box stage transitions (e.g. corner A to corner B). |
| `area_designation_tool_changed(tool_id: String, tool_label: String)` | `AreaDesignationController` | `AreaDesignationHud` | Active area designation tool changes. |
| `area_designation_tool_selected(tool_id: String, target_area_id: String)` | `DesignationMenu` | `Player`, `AreaDesignationController` | Tool or area chosen from Designation Menu (**T**). |
| `harvest_box_toggled(active: bool)` | `Player` | `HarvestBoxController`, `HUD` | Player toggles harvest designation box mode. |
| `build_menu_toggled(open: bool)` | `Player` | `InstructionsLabel`, `HUD` | Build menu opened or closed (**B**). |
| `buildable_selected(id: String)` | `BuildMenu` | `BuildController`, `Player` | Buildable selected in menu; transitions to placement mode. |
| `furniture_placed(def_id: String, anchor: Vector3i)` | `FurnitureLayer` | `Colony`, `GameLog`, `PlantSpawner` | Furniture placed in world. |
| `furniture_removed(def_id: String, anchor: Vector3i)` | `FurnitureLayer` | `Colony`, `GameLog`, `PlantSpawner` | Furniture deconstructed or removed from world. |
| `blueprint_placed(target_def_id: String, anchor: Vector3i, blueprint: Node)` | `BlueprintLayer` | `Colony` | Blueprint placed; spawns construction or hauling Job on JobBoard. |
| `blueprint_removed(target_def_id: String, anchor: Vector3i)` | `BlueprintLayer` | `Colony`, `JobBoard` | Blueprint removed; cancels associated construction job. |
| `blueprint_materials_ready(target_def_id: String, anchor: Vector3i, blueprint: Node)` | `Blueprint` | `Colony` | Blueprint materials satisfied; promotes haul job to construction. |
| `crafting_order_queued(station: Node, anchor: Vector3i)` | `CraftingStation` | `Colony` | Craft order queued; spawns hauling job to feed station. |
| `crafting_materials_ready(station: Node, anchor: Vector3i)` | `CraftingStation` | `Colony` | Station materials satisfied; spawns crafting work job. |
| `harvest_mark_toggled(furniture: Node, anchor: Vector3i, is_marked: bool)` | `Harvestable` | `Colony` | Flora or crop marked for harvest; spawns or cancels harvest job. |
| `plot_needs_sowing(growable: Node, anchor: Vector3i, crop_id: String, needed: bool)` | `Growable` | `Colony` | Farm plot requires seed planting; spawns or cancels sow job. |
| `plot_needs_water(growable: Node, anchor: Vector3i, needed: bool)` | `Growable` | `Colony` | Farm plot requires hydration; spawns or cancels water job. |
| `plot_needs_tending(growable: Node, anchor: Vector3i, needed: bool)` | `Growable` | `Colony` | Farm plot requires tending; spawns or cancels tend job. |
| `item_picked_up(item_id: String, count: int)` | *(none yet)* | *(none yet)* | Declared but unwired: nothing emits or connects it (see [Tech Debt](tech-debt.md)). |
| `job_logged(entry: Dictionary)` | `JobBoard` | `JobLogUI` | Diagnostic event for job failure or dispatch telemetry. |
| `command_mode_requested(colonist_ids: Array)` | UI / interaction | `CommandController` | Enters tactical command mode targeting specified colonists. |
| `deploy_orders_issued(target_positions: Dictionary)` | `CommandController` | `Colony`, `JobBoard` | Commits tactical move/deploy orders for colonists. |

---

## Content Directory Loading

`subsystems/core/content_dir_loader.gd` (`class_name ContentDirLoader`, static-only,
mirrors `AIUtils`'s pattern) is the shared scan behind every `id → def` content
registry: `ItemDB`, `EnemyLibrary`, `CropLibrary`, `ColonistNeeds`, `BuildLibrary`,
and `BlockLibrary`. `ContentDirLoader.load_by_id(dir_path, is_valid_type)` recurses
into subdirectories, `load()`s each matching file, and indexes it by its `id` field
(skipping — with a warning, never silently or in a loop — any resource whose `id` is
empty). Because content identity is always the `id` field and never the filename or
path (see Data Conventions below), a category's `data/<category>/` folder can be
split into nested subfolders as it grows without any loader code changes.
`MapLibrary` is the one exception: its `data/maps/<id>/map_def.tres` shape (fixed
filename per id-subfolder, not "scan every `.tres` in a dir") doesn't fit this
helper and is scanned directly instead.

---

## Multiplayer Readiness

While networking implementation (RPCs, state replication, server authority) is deferred to post-MVP, the codebase adheres to the following multiplayer-ready architectural rules:

1. **Voxel World Choke-Point:** All voxel modifications and queries must route through `BlockyGrid` / `SmoothGrid` (implementing `IBlockGrid`). Never touch raw `voxel_tool` directly from gameplay code. This preserves a single point for injecting future network RPCs.
2. **Player Identity & Reference:** Never assume a single player node or query `get_tree().get_first_node_in_group("player")`. Gameplay actions should obtain the acting player reference via `GameState.get_local_player()` or through explicit event payloads.
3. **Deterministic Randomness:** Use `GameState.rng` (`RandomNumberGenerator`) for gameplay random number queries rather than global `randi()`/`randf()`, enabling seed sharing across peers.
4. **Input Decoupling:** Keep input detection isolated in `InputComponent` rather than calling `Input` functions directly inside character movement/physics loops, allowing transparent substitution with network-replicated input components.
