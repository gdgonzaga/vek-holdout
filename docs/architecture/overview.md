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
│   ├── furniture/      # Furniture runtime node (placed-item instance)
│   ├── colonists/      # Colonist entity, animation controller, voxel pathfinder, roster
│   ├── ai/             # AI Subsystem: LimboAI integration, ColonistBrain, ColonistNeeds, BT tasks
│   ├── jobs/           # Fractional job system: JobInstance, WorkerClaim
│   ├── skills/         # SkillSet/skill progression
│   ├── combat/         # Planned — damage resolution, weapons, enemy base (empty)
│   ├── equipment/      # Planned — equipment component, loadout templates (empty)
│   ├── raids/          # Planned — raid scheduler, threat direction (empty)
│   ├── expeditions/    # ExpeditionManager: POI discovery, expedition lifecycle
│   ├── maps/           # MapLibrary catalog, MapWiring, SpawnHelpers
│   ├── loot/           # Planned — loot tables, container logic (empty)
│   ├── inventory/      # Weight-based inventory, ItemDef, ItemDB
│   ├── crafting/       # Recipe model, station logic, craft-Job flow
│   ├── farming/        # Growable component, CropLibrary — crop lifecycle
│   ├── harvesting/     # Harvestable component — work-time + yield resolution
│   ├── mining/         # Dig box designation controller, 3D preview, markers
│   └── actions/        # Interaction runtime + data: InteractionComponent, GameAction
├── ui/                 # HUD + all full-screen UIs
│   ├── hud/
│   ├── interaction/
│   ├── log_feed/
│   ├── log_history/
│   ├── build_menu/
│   ├── storage/
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

---

## Subsystems Overview

| Subsystem | Folder | Description |
|---|---|---|
| Core | `subsystems/core/` | Root scene, Main orchestrator, time, save management. |
| Voxel / World | `subsystems/voxel/` | Dual voxel engine wrappers (`BlockyGrid`, `SmoothGrid`). |
| Player | `subsystems/player/` | Character controller, camera rig, interaction input. |
| Build | `subsystems/build/` | Blueprint placement, catalog library, ghost previews. |
| Actions & Interaction | `subsystems/actions/` | E-key menu options, conditions, interaction component. |
| Functional Rooms | `subsystems/functional_rooms/` | Room capability tracking based on placed furniture. |
| Colonists | `subsystems/colonists/` | Colonist entities, animation controller, pathfinding. |
| Jobs | `subsystems/jobs/` | Job registry, `JobInstance`, `WorkerClaim` fractional reservations. |
| AI & Behavior Trees | `subsystems/ai/` | LimboAI engine, `ColonistBrain` Utility AI, `ColonistNeeds`, BT tasks. |
| Pathfinding & Navigation | `subsystems/colonists/` | Voxel A* 3D pathfinder (`VoxelPathfinder`). |
| Skills | `subsystems/colonists/` | Entity L1-L5 skill progression and work multipliers. |
| Maps | `subsystems/maps/` | Map loading, per-map scenes, wiring helpers. |
| Expeditions | `subsystems/expeditions/` | POI discovery, expedition departure and return lifecycle. |
| Inventory | `subsystems/inventory/` | Weight-based inventory, items, carrying capacity. |
| Crafting | `subsystems/crafting/` | Workbench/Forge station recipes and craft jobs. |
| Farming | `subsystems/farming/` | Farm plot growables, hydration, crop lifecycle. |
| Mining | `subsystems/mining/` | Dig box designation, strata materials, designation markers. |
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
| **Colony** | `colony.gd` | Colony roster and JobBoard singleton owner. |
| **TimeSystem** | `time_system.gd` | Continuous time advance and day rollover signals. |
| **RunProgress** | `run_progress.gd` | Run-scoped unlocked content tracking. |
| **BuildLibrary** | `build_library.gd` | Buildable catalog index. |
