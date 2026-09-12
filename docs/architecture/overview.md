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

`subsystems/loot/` does not exist yet — Loot is design-only (see [Loot](loot.md)). Functional Rooms
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
| Colonists | `subsystems/colonists/` | Colonist entities, animation controller, pathfinding. |
| Jobs | `subsystems/jobs/` | Job registry, `JobInstance`, `WorkerClaim` fractional reservations. |
| AI & Behavior Trees | `subsystems/ai/` | LimboAI engine, `ColonistBrain` Utility AI, `ColonistNeeds`, BT tasks. |
| Pathfinding & Navigation | `subsystems/colonists/` | Voxel A* 3D pathfinder (`VoxelPathfinder`). |
| Skills | `subsystems/colonists/` | Entity L1-L5 skill progression and work multipliers. |
| Maps | `subsystems/maps/`, `subsystems/map_authoring/` | Map loading, per-map scenes, wiring helpers, map-editor stamping tools. |
| Expeditions | `subsystems/expeditions/` | POI discovery, expedition departure and return lifecycle. |
| Inventory | `subsystems/inventory/` | Weight-based inventory, items, carrying capacity. |
| Crafting | `subsystems/crafting/` | Workbench/Forge station recipes and craft jobs. |
| Farming | `subsystems/farming/` | Farm plot growables, hydration, crop lifecycle. |
| Wild Flora | `subsystems/environment/` | Wild flora lifecycle, perennial foraging, real-time felling, and tree scattering. |
| Hunger | `subsystems/colonists/` | Physiological satiety tracking, FoodParams, starvation, and LimboAI feeding. |
| Recreation | `subsystems/furniture/` | RecreationParams capability, occupancy slot rationing, recreation need satisfaction. |
| Mining | `subsystems/mining/` | Dig box designation, strata materials, designation markers. |
| Combat | `subsystems/combat/` | HealthComponent, EnemyBase, turret defenses, hostile behavior trees. |
| Equipment | `subsystems/equipment/` | 8-slot gear component, EquipmentVisualizer, EquipmentAudit fulfillment. |
| Raids | `subsystems/raids/` | NightRaidController, radial enemy spawning, spawn-rate pacing curves. |
| Loot | — (planned) | Loot tables and container rolls for scavenge missions — spec only, see [Loot](loot.md). |
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
| **BuildLibrary** | `subsystems/build/build_library.gd` | Buildable catalog index. |
| **Tools** | `subsystems/autoloads/tools.gd` | Cross-subsystem utility helpers (e.g. UUID generation). |
| **MapLibrary** | `subsystems/maps/map_library.gd` | `id → MapDef` map catalog registry. |
| **ItemDB** | `subsystems/inventory/item_db.gd` | `id → ItemDef` item catalog registry. |
| **ExpeditionManager** | `subsystems/expeditions/expedition_manager.gd` | POI discovery and expedition lifecycle. |

Order above matches `project.godot`'s `[autoload]` section — later autoloads may depend on earlier ones being ready.

---

## Multiplayer Readiness

While networking implementation (RPCs, state replication, server authority) is deferred to post-MVP, the codebase adheres to the following multiplayer-ready architectural rules:

1. **Voxel World Choke-Point:** All voxel modifications and queries must route through `BlockyGrid` / `SmoothGrid` (implementing `IBlockGrid`). Never touch raw `voxel_tool` directly from gameplay code. This preserves a single point for injecting future network RPCs.
2. **Player Identity & Reference:** Never assume a single player node or query `get_tree().get_first_node_in_group("player")`. Gameplay actions should obtain the acting player reference via `GameState.get_local_player()` or through explicit event payloads.
3. **Deterministic Randomness:** Use `GameState.rng` (`RandomNumberGenerator`) for gameplay random number queries rather than global `randi()`/`randf()`, enabling seed sharing across peers.
4. **Input Decoupling:** Keep input detection isolated in `InputComponent` rather than calling `Input` functions directly inside character movement/physics loops, allowing transparent substitution with network-replicated input components.
