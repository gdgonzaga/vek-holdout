# Architecture — Vek: Holdout

Last updated: 2026-07-31 (Voxel/World + Functional Rooms drift resolved)

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
│   ├── expeditions/    # Scavenge mission, world map, POI
│   ├── loot/           # Loot tables, container logic, Key Item pool
│   ├── inventory/      # Items, stacks, inventory model
│   └── crafting/       # Recipe model, station logic, craft-Job flow
├── ui/                 # HUD + all full-screen UIs (kept at project root for now)
│   ├── hud/
│   ├── build_menu/
│   ├── player_screen/
│   ├── colony_screen/
│   ├── world_map/
│   ├── pause_menu/
│   ├── main_menu/
│   ├── game_over/
│   ├── day_summary/
│   ├── settings/
│   └── shared/         # Reusable subscenes (health_bar, inventory_slot, roster_row, job_log_entry, memorial_entry)
├── data/               # All .tres/.json data (centralized)
│   ├── characters/     # CharacterDef per type (player, colonist, companion, brawler, shooter)
│   ├── blocks/         # Block definitions (wood/scrap/stone/metal/reinforced)
│   ├── buildables/     # BuildableDef (player-placed objects: pole, etc.)
│   ├── colonists/      # Colonist definitions + AI (ColonistDef, colonist_ai)
│   ├── furniture/      # FurnitureDef (is_functional + functional_area) — schema pending (C1)
│   ├── items/          # Item definitions
│   ├── loot/           # Loot tables (standard.tres, deep.tres) + key_items.tres pool
│   ├── loadouts/       # Loadout templates (player-created + saved per run)
│   ├── recipes/        # Recipe definitions (workbench.tres, forge.tres)
│   ├── skills/         # Skill definitions (6 skills) + use-curves + level multipliers
│   ├── game_config.tres    # Engine-level constants
│   ├── energy_config.tres      # Planned — Global Stamina thresholds/floors + Breath rates (Energy subsystem)
│   ├── raid_curve.tres         # Planned — Raid escalation table (Raids subsystem)
│   └── starting_conditions.tres # Planned — Day-1 resources/equipment/structure (§9; C7)
├── debug/              # Debug console (dev/playtest only; stripped from release)
├── tests/              # Automated unit/integration tests (run in CI / headless)
└── testing/            # Manual playtest scenes (developer-run, not shipped)
```

**Placement rules:** subsystem folder = architecture section by default. Ambiguous ownership → `core/`. Autoloads always in `subsystems/autoloads/`. All data in `data/` (centralized, not scattered). Playtest/manual scenes go in `testing/`, automated tests in `tests/`. UI scenes live in `ui/` (project root), not under `subsystems/`.

## Scene Tree Overview

- **Main** (`main.tscn`) — root scene, persists across entire game session. Owns the scene-transition machinery and the always-on CanvasLayers.
  - CanvasLayer (`layer=10`) — UI overlay layer
    - **HUD** (`hud.tscn`) — persistent in-game overlay (HP/Durability/Stamina/Breath bars, hotbar, build-mode ghost). Instanced by Main at startup; hidden during full-screen menus.
  - CanvasLayer (`layer=20`) — Full-screen UI layer (Player/Colony/Map/Pause/MainMenu/GameOver/Settings). Only one present at a time.
  - **WorldRoot** (`world.tscn`, root script `world.gd` — `World`) — the current game world; swapped by SceneManager on base↔POI transitions. Structural container only; no gameplay logic.
    - VoxelGrid (Node, `voxel_grid.gd`) — the `IBlockGrid` owner; sole voxel_tool access point
      - VoxelTerrain (`voxel_tool` blocky mode)
    - **Player** (`player.tscn`)
    - ColonistContainer (Node3D) — holds active colonist instances
    - EnemyContainer (Node3D) — holds active enemy instances
    - FurnitureContainer (Node3D) — holds free-standing furniture placed at runtime (Build subsystem)
    - BuildController (`build.tscn`) — active only in Blueprint mode
- **Boot** (`boot.tscn`) — project entry point; loads Main + Main Menu. (Alternative: Main is the entry point and Main Menu is a CanvasLayer. Pick one in implementation — see Tech Debt.)

**Scene transitions:** SceneManager swaps `WorldRoot` between the base scene and POI scenes. Full-screen UIs replace each other in the `layer=20` CanvasLayer. The HUD stays mounted throughout gameplay; hidden when any full-screen UI opens (pause/menu) per §12 "full pause everywhere."

## Autoloads / Singletons

Only scripts genuinely needed across multiple unrelated scenes. Solo project — minimal.

| Name | Script | Responsibility |
|---|---|---|
| **GameState** | `game_state.gd` | Run-level state: current day, time-of-day, save slot, pause state, current scene (base vs POI). Emits state-change signals (NOT through EventBus). |
| **EventBus** | `event_bus.gd` | Global signal relay for cross-scene events only (see registry). |
| **SceneManager** | `scene_manager.gd` | Load/unload WorldRoot with transitions; manage UI layer swaps. |
| **SaveSystem** | `save_system.gd` | Autosave on sleep/midnight/quit; load on Continue/New Game. |
| **Colony** | `colony.gd` | The colony roster + Job Board. Cross-scene because base and POI scenes both need it (colonists stay in colony during expeditions). |
| **TimeSystem** | `time_system.gd` | Continuous time advance, day boundary (midnight) event, links to Stamina accrual. Cross-scene because time advances in both base and POI. |
| **RunProgress** | `run_progress.gd` | Run-scoped *earned* state. Currently holds buildable unlocks; **intended to grow into the home for Colony's run-state children** (Memorial, KeyItemPool, LoadoutManager, DiscoveredGear) and other run-earned state — migration ongoing. A "dumb bag" of ids only (no data-def reading). Reset by the New Game orchestrator, then reseeded by `EventBus.run_started`. Saved with the run, wiped on New Game. |
| **BuildLibrary** | `build_library.gd` | The read-only catalog of everything buildable. Loads every `BuildableDef` subclass (`BlockDef`, `BuildableDef`, `FurnitureDef`) from `data/blocks/`, `data/buildables/`, `data/furniture/` into one `id → def` map. "What's unlocked" is delegated to `RunProgress` — this catalog seeds the default-unlocked defs at startup and on `EventBus.run_started`, then exposes `is_unlocked` / `get_unlocked` / `unlock` / `get_def`. Read-only after `_ready`. See Build subsystem. |
| **Tools** | `tools.gd` | General cross-subsystem utilities. Currently: `generate_uuid() -> String` (cryptographically random RFC 4122 UUID v4). |

**Deliberately NOT autoloads** (kept as scene-scoped references):
- Inventory — belongs to the player; accessed via the Player node.
- Inventory (shared colony storage) — accessed via StorageCrate nodes; no global needed.
- Raid scheduler — base-scene only; expeditions don't trigger base raids during the mission (raid resolves on return).
- Threat-direction weights — part of Colony state, but only base scene reads them at raid time.

### EventBus Signal Registry

Authoritative list of `event_bus.gd` signals. Cross-scene only.

| Signal | Emitted by | Listeners | Purpose |
|---|---|---|---|
| `run_started()` | New Game orchestrator | RunProgress seeders (BuildLibrary, etc.) | New Game reset complete; seeders re-add default unlocks to RunProgress (additive — safe to run repeatedly) |
| `day_rolled_over(new_day: int)` | `time_system.gd` | `save_system.gd`, HUD, raids scheduler | Midnight crossed; triggers autosave + Day Summary prep |
| `raid_started(raid_data: Dictionary)` | raids subsystem | HUD, Colony (stance assignment), colonists | Begin raid sequence |
| `raid_ended(outcome: Dictionary)` | raids subsystem | HUD, Colony, save_system | Raid resolved; unlock player control |
| `expedition_started(crew: Array, poi_id: String)` | expeditions subsystem | SceneManager, Colony, colonists | Travel to POI scene |
| `expedition_ended(result: Dictionary)` | expeditions subsystem | SceneManager, Colony, HUD | Return to base scene |
| `colonist_died(colonist_id: String)` | combat subsystem | Colony, HUD, Memorial | Named colonist death; adds to memorial roster |
| `player_died(context: String)` | combat subsystem | GameState, HUD | Player HP hit 0 (respawn handling) |
| `game_over()` | GameState | SceneManager | All colonists + player dead; load Game Over scene |
| `blueprint_mode_toggled(active: bool)` | player subsystem | BuildController, HUD | Mode layer change |
| `buildable_selected(id: String)` | player subsystem | BuildController | Player selected a buildable in the build menu (sets the controller's `selected_id`) |
| `furniture_placed(def_id: String, anchor: Vector3i)` | FurnitureLayer | Colony (Functional Rooms) | Furniture placed in world — increments the relevant Functional Rooms counter |
| `furniture_removed(def_id: String, anchor: Vector3i)` | FurnitureLayer | Colony (Functional Rooms) | Furniture removed from world — decrements the relevant Functional Rooms counter |
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
- **Cross-scene → EventBus.** Anything that must cross a WorldRoot swap (base↔POI) or reach a CanvasLayer from the world goes through EventBus.
- **GameState changes → GameState signals.** `day_changed`, `pause_state_changed` etc. are emitted by GameState and connected directly. Do NOT relay these through EventBus.
- **Colonist/job state → Colony (autoload).** The roster and Job Board live on Colony; UI reads/writes via Colony's public methods. Colony emits its own signals for roster changes.
- **Signals describe events, not commands.** `colonist_died`, not `kill_colonist`.

## Key Conventions

- Every script, scene, and data file must belong to a documented subsystem. Ambiguous → `core/`.
- All data (block stats, enemy stats, loot tables, raid curves, armor Durability values, item defs) lives in `res://data/` as `.tres` Resource files. No hardcoded content values in scripts.
- Voxel-specific code is isolated to `voxel/`. No other subsystem imports `voxel_tool` directly — they go through `voxel/`'s interfaces (see Build subsystem's grid adapter).
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

## Known Tech Debt

- [ ] **Boot vs Main scene strategy undecided** — either `boot.tscn` loads Main + MainMenu, or Main is the entry and MainMenu is a CanvasLayer. Decide on first implementation; document here.
- [ ] **voxel_tool raycast reliability** — `VoxelTool.raycast()` is unreliable (see `gotchas/voxel_tool_raycast.md`); the workaround uses Godot physics raycast against voxel collision bodies. Validate this still works when build mode lands.
- [ ] **Colonist pathfinding split** — A* on voxel grid for colonists, NavigationAgent for enemies. Two pathfinding systems in one game is complexity; validate the split pays off vs. NavAgent-for-everything once both are prototyped.
- [ ] **`combat/` accumulating shared character-stat components** — HealthComponent, BreathComponent, StaminaComponent all live in `combat/` but are general-purpose character components (used by player/colonists/enemies). Consider a `core/components/` home if a fourth such component appears.
- [~] **Colony autoload accumulating run-state children** — Memorial (deceased roster), KeyItemPool (once-per-playthrough enforcement), LoadoutManager (templates + assignments), and DiscoveredGear (item-possession tracking) all live on Colony because their state must persist across base↔POI scene swaps and be saved. **Resolved (in progress):** the `RunProgress` autoload has been created as the intended home for this run-state, and currently holds buildable unlocks. It is *growing* — additional run-earned state (and the eventual migration of Colony's four children) lands here as subsystems come online. In the interim, Memorial / KeyItemPool / LoadoutManager / DiscoveredGear still live on Colony.
- [ ] **Debug console release-stripping approach undecided** — the console is dev-only and must not ship in release builds. Options: (a) Godot export profile excludes the `debug/` folder, (b) `OS.is_debug_build()` gate around the autoload registration, (c) both. Decide before first export; document here.

## Unimplemented Subsystems

> GDD systems that have a design spec but **no architecture yet**. Each needs a subsystem section (Files + Signals + Flow Traces + Class Reference) before it can be built. Grouped by how much design work remains vs. how much is pure architecture coverage.

### Needs design decisions before architecting

**Companion + Day-1 incapacitated state** — GDD §6.6 + §9
The companion is a special colonist (+20% HP, fixed narrative identity, starts incapacitated in the ruined shelter). The Day-1 forced sequence is: scavenge → craft Clinic Bed → revive companion. **Missing:** no Companion class/subclass on ColonistBase, no "incapacitated" state machine, no revival flow at the Clinic Bed, no bootstrapping logic that places the companion + ruined shelter at New Game. The `+20% HP` is mentioned only as a parenthetical on ColonistBase.max_hp.
*Consumers:* §9 Starting Conditions (New Game bootstrap), Clinic Bed (revival interaction), permadeath (companion death is presumably game-relevant).
*Open design questions:* Is the companion a ColonistBase subclass or a flag? What does "incapacitated" mean mechanically (can't be targeted by enemies? invulnerable? just inactive?)? Does companion death end the game (separate from the all-colonists-dead rule)?

**Recruitment** — GDD §6.9
Two MVP recruitment sources: random world events (stranger at the gate) and radio contacts (via Command Desk). **Missing:** no recruitment subsystem, no event-source architecture (world-event spawner, radio-contact scheduler), no recruitment-event data, no "stranger arrives" notification flow. `Colony.add_colonist()` exists but has no caller.
*Consumers:* Colony roster growth (the path from solo+companion to the MVP cap of 5).
*Open design questions:* How are world events scheduled (timer-based? triggered by colony milestones?)? What does a "radio contact" look like mechanically (player-initiated at the Command Desk, or auto-offered)? Are recruits named or unnamed (ties to B12)?

**Named vs unnamed colonists** — GDD §6.5
Named colonists have backstories + may start with higher skill levels; unnamed are generic. The distinction controls memorial eligibility (per §17 Permadeath, named get entries; unnamed do not — though the GDD also says "permadeath applies equally to named and unnamed"). **Missing:** no `is_named` flag on ColonistBase, no narrative-identity field, no skill-level-bonus application for named recruits.
*Consumers:* Memorial roster (B1 stub currently appends all deaths equally — should it filter?), recruitment (B10 — are recruits named or unnamed?), Day Summary Fallen section.
*Open design questions:* Does "named vs unnamed" actually affect memorial eligibility, or was the GDD's "named get memorial entries; unnamed do not" superseded by "permadeath applies equally"? The two statements are in tension. Also: what fraction of recruits are named?

### Mostly specced — needs architecture coverage

**Encounter templates** — GDD §5 (MVP Encounter Templates)
Three ready-to-use configs for testing and scavenge missions: Template 1 Basic (2× Brawler), Template 2 Standard (2× Brawler + 1× Shooter), Template 3 Hard (3× Brawler + 2× Shooter). Each specifies enemy composition + positioning. **Missing:** no encounter-definition data file, no spawner that reads them, no link between templates and POI difficulty tiers. The `spawn_wave` debug command and the SpawnManager exist but don't reference templates.
*Consumers:* Expeditions (scavenge missions need to spawn per-difficulty), playtesting (the templates are explicitly for testing).
*Open design questions:* Are templates the same data structure as raid waves, or separate? (Probably the same — both feed SpawnManager.) How do POI difficulty tiers (Easy/Normal/Hard per §17) map to templates?

**Demolition (as a Job)** — GDD §7.5
Block removal rate = 2× build rate (`tool repair amount × 2 × rate of fire`). Currently only the low-level `VoxelGrid.remove_block_at(pos)` primitive exists. **Missing:** no demolition-as-Job flow (a colonist paths to a marked block and removes it over time), no "mark for demolition" UI/placement, no Job-Board registration of demolition jobs. The player can presumably demolish instantly via build mode, but colonist-driven demolition isn't architected.
*Consumers:* Base reorganization, breach repair (clearing destroyed-block debris).
*Open design questions:* Is demolition player-instant (RMB in build mode) AND colonist-Job (for larger demolitions), or one or the other? Does demolition produce reclaimed materials (partial refund) or just remove?

**Colonist capacity / bed-capping** — GDD §6.8
Max colony size is tied to Colonist Bed count (1 bed = 1 colonist slot; MVP cap 5, hard cap 10). **Missing:** no bed-count → cap enforcement logic, no recruitment gate (Colony.add_colonist doesn't check capacity), no signal when a bed is built/destroyed (which should raise/lower the cap).
*Consumers:* Recruitment (B10 — must check capacity before adding), Colony Management Roster tab (display cap), save system (persist bed count).
*Open design questions:* What happens if a bed is destroyed while a colonist is assigned to it (does the colonist leave? become "homeless"?). Already partially answered by Functional Rooms (bed is functional furniture, count tracked) but the cap-enforcement side isn't.

### Smaller improvements (D-items)

**New-Game reset flow** — GDD §8 (Game Over) + §17 Save
New game wipes all state including map reveal. **Missing:** no reset class/flow; SaveSystem loads but nothing owns the "clear everything for a fresh run" operation. Should enumerate every piece of run-state (GameState, Colony + its 4 children, voxel world, map reveal, player/colonist inventories, skills, loadouts, raid stances) and zero it.

**Game Over evaluator** — GDD §8
The `game_over()` EventBus signal exists, but nothing checks the "all colonists AND player dead" condition. **Missing:** an evaluator (probably on Colony or a dedicated component) that listens to `colonist_died` + `player_died` and emits `game_over()` when both rosters are empty.

**Structural weak-point targeting** — GDD §17 Raids
Brawlers attack the lowest-HP block in range; Shooters path through the lowest-resistance opening (open gates first, then Scrap blocks, then damaged blocks). **Missing:** the targeting logic / structural-analysis pass that evaluates the perimeter for weak points and is consumed by enemy AI. The low-level primitive it would build on now exists: `VoxelGrid` exposes `get_hp_at` / `has_block_at` / `apply_damage` and the `block_destroyed` signal — so per-block HP querying and damage are available; what's still needed is the perimeter-scoring + AI-consumption layer.

**Travel-time-proportional-to-distance** — GDD §17 Day/Night
"Travel time proportional to POI distance. Longer travel = more time passes = more Stamina drained." **Missing:** the proportional-distance calculation isn't specced (distance metric? time-per-unit-distance?).

**Save serializes voxel world** — flagged in Tech Debt
Zylann's `voxel_tool` has its own save format; integrating it with the game's save slots needs design. Currently a Tech Debt item; may warrant elevation to a real decision before the save system is built.

**Player input map data file** — GDD §4 has a full key map; ARCH has no corresponding `data/input_map.tres` or similar. Minor — could be hardcoded in InputMap at the project level rather than a data file, but the GDD implies it's data.

### Data schemas still missing (C-items)

These data folders are *referenced* in Files tables but have no formal schema in the Data Schemas section. Low-decision work; mostly mechanical once the owning subsystem is settled:

- **C1** `data/furniture/` — 16 buildables (Clinic Bed, Workbench, Forge, etc.). Needs `is_functional` + `functional_area` fields per the Functional Rooms subsystem.
- **C6** `data/tools/` — Hammer, Nailgun (repair value, RoF, range).
- **C7** `data/starting_conditions.tres` — Day-1 resources/equipment/structure (GDD §9). Referenced in Core Files but never schema'd.
- **C8** `data/pois/` — POI definitions (1 for MVP). Referenced in Expeditions Files.
- **C9** Schemas for already-referenced folders: `data/labors/`, `data/weapons/`, `data/armor/`.

---

## Subsystem: Core

The root scenes, shared utilities, global UI shell, save system, and time. Other subsystems reference Core's autoloads and scenes.

### Files

| File | Type | Responsibility |
|---|---|---|
| `main.tscn` / `main.gd` | Scene/Script | Root scene; owns CanvasLayers and WorldRoot. Bootstraps HUD at startup. Does NOT contain gameplay logic. |
| `boot.tscn` (or Main as entry — TBD) | Scene | Project entry; loads Main + MainMenu. |
| `../autoloads/game_state.gd` | Autoload | Run-level state + state-change signals. Does NOT own save logic (that's SaveSystem). |
| `../autoloads/event_bus.gd` | Autoload | Cross-scene signal relay only. No state. |
| `../autoloads/scene_manager.gd` | Autoload | Scene swap (base↔POI) + UI layer management. Does NOT own UI content (each screen is its own scene). |
| `../autoloads/save_system.gd` | Autoload | Autosave (sleep/midnight/quit) + load. Serializes run state: GameState (day/scene/slot), Colony (roster + job board + Memorial + KeyItemPool.found), voxel world, world-map reveal, player/colonist inventories + loadouts + raid stances. Does NOT decide when to save (callers do). |
| `../autoloads/time_system.gd` | Autoload | Continuous time advance; emits `day_rolled_over`. Links to Stamina accrual. |
| `../data/game_config.tres` | Data | Engine-level constants (gravity, target FPS). See Data Schema. |
| `../data/starting_conditions.tres` | Data | Day-1 resources/equipment/structure (GDD §9). See Data Schema. |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `day_rolled_over(new_day)` | `time_system.gd` | SaveSystem, HUD, raids | Yes | Sleep→Day Summary, Raid Schedule |
| `day_changed(new_day)` | `game_state.gd` | HUD | No (GameState signal) | — |
| `pause_state_changed(paused)` | `game_state.gd` | All sim nodes | No (GameState signal) | Pause Menu |
| `save_slot_changed(slot)` | `game_state.gd` | SaveSystem | No (GameState signal) | New Game / Load |

### Flow Trace: Sleep → Day Summary → Save

**Trigger:** Player interacts with bed (E) while in base scene.

1. Player emits `sleep_requested` (direct ref) → Main handles.
2. Main calls `TimeSystem.advance_to_midnight()` → TimeSystem emits `day_rolled_over(new_day)` via EventBus.
3. SaveSystem listens → serializes state (GameState, Colony, voxel world) to current save slot.
4. Player Durability auto-recovers to full (MVP interim — see GDD §6.11).
5. Stamina + Breath reset to 100% for all entities (see Energy subsystem Sleep flow for the canonical detail).
6. Day Summary screen opens (CanvasLayer 20) showing the day's events.
7. Player dismisses Day Summary → returns to base scene at dawn (new day).

**End state:** New day begun, state saved, Durability reset, Stamina + Breath reset to 100%, Day Summary shown.

### Flow Trace: Pause Menu (full pause)

**Trigger:** Player presses Esc during gameplay.

1. Player input handler detects Esc → calls `GameState.set_paused(true)`.
2. GameState emits `pause_state_changed(true)`.
3. All simulation nodes (WorldRoot + children) get `process_mode = PROCESS_MODE_DISABLED`.
4. PauseMenu scene loads in CanvasLayer 20; HUD hidden.
5. Player clicks Resume → `GameState.set_paused(false)` → inverse of above.

**End state:** Simulation frozen, Pause Menu visible, Resume returns to prior state.

### Class Reference

#### Class: GameState

**Extends:** Node
**Script:** `game_state.gd`
**Description:** Run-level state holder. Holds current day, scene ID, pause state, save slot. Emits signals on its own state changes — these are NOT routed through EventBus.
**Used by:** HUD (day/pause), all scenes (pause checks), SaveSystem.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `current_day` | `int` | [export default 1] Current in-game day. |
| `current_scene_id` | `String` | `"base"` or `"poi_<id>"`. |
| `paused` | `bool` | True when any full-screen menu is open. |
| `save_slot` | `String` | Current save slot name; empty if none loaded. |
| `world_root` | `Node` | Reference to the WorldRoot whose children get `process_mode`-toggled on pause. Set by Main when it mounts the WorldRoot; `null` until then. |

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
| `set_paused(p: bool) -> void` | Toggles pause; emits `pause_state_changed`; sets `process_mode` on `world_root` (and its children). |
| `advance_day() -> void` | Increments `current_day`; emits `day_changed`. Called by TimeSystem. |
| `set_scene_id(scene_id: String) -> void` | Sets `current_scene_id`; emits `scene_changed`. Called by SceneManager on swap completion. |
| `set_save_slot(slot_name: String) -> void` | Sets `save_slot`; emits `save_slot_changed`. Called on New Game / Load. |

---

## Subsystem: Voxel / World

The buildable blocky-voxel world. Wraps Zylann's `voxel_tool` plugin. All voxel coupling lives here — other subsystems (Build) interact via the `IBlockGrid` interface, never `voxel_tool` directly.

### Files

| File | Type | Responsibility |
|---|---|---|
| `world.tscn` / `world.gd` | Scene/Script | The WorldRoot (`World`, structural container only — no gameplay logic). Holds VoxelGrid + containers for player/colonists/enemies/furniture. |
| `voxel_grid.gd` | Script | Implements `IBlockGrid` (in `build/`); wraps `voxel_tool` get/set + the Godot-physics raycast (see `gotchas/voxel_tool_raycast.md`). Owns block get/set, per-cell HP, and the damage surface. Does NOT own placement UX (that's Build). |
| `block_library.gd` | Script (Resource) | Owns the `VoxelBlockyLibrary` the mesher renders with; maps string block_id ↔ integer library index, and id → `BlockDef`. Enforces the index convention (0 = air, terrain = 1) and bakes the library from `data/blocks/`. |
| `../data/blocks/` | Data | One `.tres` per block type (wood, scrap, stone, metal, reinforced, terrain). See Data Schema. |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `block_placed(pos: Vector3i, block_id: String)` | `voxel_grid.gd` | Build (ghost validation), colonists (pathfinding re-bake) | No (same scene) | Place Blueprint |
| `block_destroyed(pos: Vector3i)` | `voxel_grid.gd` | colonists (pathfinding), raids (breach detection) | No | Enemy Attack Block |

### Flow Trace: Player targets a block (raycast)

**Trigger:** Build mode active; player moves cursor.

1. BuildController fires Godot physics raycast from camera each frame.
2. On hit, computes voxel index via `floor(hit.position - hit.normal * 0.001)` (per gotcha).
3. Queries `VoxelGrid.get_block_at(pos)` to determine target validity (empty/full, owned).
4. Updates ghost preview position + validity tint.

**End state:** Ghost preview shows valid/invalid placement under cursor.

### Class Reference

#### Class: World

**Extends:** Node3D
**Script:** `world.gd`
**Description:** The WorldRoot — the current game world, swapped by SceneManager on base↔POI transitions. A structural container only; holds no gameplay logic. The voxel world's behavior lives in `VoxelGrid` / `BlockLibrary`.
**Used by:** SceneManager (swaps the whole node), subsystems that fetch their containers/grid via the accessors.
**Lifecycle:** `@onready` resolves its child refs at `_ready`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `voxel_grid` | `VoxelGrid` | `@onready` ref to the `VoxelGrid` child (the `IBlockGrid` owner). |
| `colonist_container` | `Node3D` | `@onready` ref; parent of active colonist instances. |
| `enemy_container` | `Node3D` | `@onready` ref; parent of active enemy instances. |
| `furniture_container` | `Node3D` | `@onready` ref; parent Node3D for free-standing furniture placed at runtime (Build subsystem). |

**Functions:**

| Function | Description |
|---|---|
| `get_grid() -> VoxelGrid` | Convenience proxy (most callers want the grid, not the world). |
| `get_terrain() -> VoxelTerrain` | Delegates to `voxel_grid.get_terrain()`. |
| `get_furniture_container() -> Node3D` | The furniture parent node. |

#### Class: VoxelGrid

**Extends:** Node
**Script:** `voxel_grid.gd`
**Description:** Implements `IBlockGrid` (defined in `build/i_block_grid.gd`). The sole owner of voxel_tool access for build/placement queries. Block identity is a string `block_id` everywhere outside this class; internally the integer voxel-tool library index is stored and `BlockLibrary` does the id↔index translation. Tracks per-position HP (`_hp_by_pos`) so combat/raids can damage blocks below their `BlockDef.hp` before destroying them.
**Used by:** Build (placement + raycast), Colonists (A* pathfinding), Raids (breach + damage), Combat (`apply_damage`).
**Lifecycle:** `_ready()` constructs the `BlockLibrary`, wires its `VoxelBlockyLibrary` into the terrain mesher, and fetches the `VoxelTool` reference from the `VoxelTerrain` child.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `terrain_path` | `NodePath` | `[export]` Path to the `VoxelTerrain` child; default `^"VoxelTerrain"`. |
| `_terrain` | `VoxelTerrain` | `@onready` ref; owns the physics world its collision bodies live in. |
| `_voxel_tool` | `VoxelTool` | Fetched in `_ready`; `mode = MODE_SET`. |
| `_library` | `BlockLibrary` | Constructed in `_ready`. |
| `_hp_by_pos` | `Dictionary` | `Vector3i -> int` (current HP; absent = air). |

**Signals:**

| Signal | Description |
|---|---|
| `block_placed(pos: Vector3i, block_id: String)` | A block was placed. Listeners: Build (ghost), colonists (re-bake), Functional Rooms (when wired). |
| `block_destroyed(pos: Vector3i)` | A block's HP hit 0 or was removed. Listeners: colonists (re-bake), raids (breach), Functional Rooms (when wired). |

**Functions:**

| Function | Description |
|---|---|
| `get_block_at(pos: Vector3i) -> String` | Returns block ID at position; empty string if air. |
| `set_block_at(pos: Vector3i, block_id: String) -> void` | Places a block; seeds `_hp_by_pos[pos] = def.hp`; emits `block_placed`. |
| `remove_block_at(pos: Vector3i) -> void` | Removes a block; clears its HP entry; emits `block_destroyed`. |
| `raycast_to_voxel(origin: Vector3, dir: Vector3, max_dist: float, exclude: Array = []) -> Dictionary` | Godot physics raycast → voxel index + face normal. Returns `{position, normal, hit}`. `exclude` is an `Array[RID]` to skip (player body). NOT `VoxelTool.raycast` (see gotcha). |
| `get_hp_at(pos: Vector3i) -> int` | Current HP of the block at pos, or 0 if air/terrain. |
| `has_block_at(pos: Vector3i) -> bool` | Whether a buildable block exists at pos (HP entry present). |
| `apply_damage(pos: Vector3i, amount: int) -> void` | Applies damage to a buildable block; destroys it (and emits `block_destroyed`) when HP hits 0. Terrain is ignored (no HP entry). |
| `get_library() -> BlockLibrary` | The block library (id↔index + def lookup). |
| `get_terrain() -> VoxelTerrain` / `get_voxel_tool() -> VoxelTool` | Accessors for consumers that need the raw handles. |

#### Class: BlockLibrary

**Extends:** Resource
**Script:** `block_library.gd`
**Description:** Registry of block types. Owns the `VoxelBlockyLibrary` the mesher renders with, maps string `block_id` ↔ integer library index, and resolves id → `BlockDef`. Assembled from `data/blocks/` in `_init()`.
**Used by:** `VoxelGrid` (mesher wiring, id↔index translation, def lookup for HP).
**Index convention:** `0` = air (`VoxelBlockyModelEmpty`); **terrain is forced to index 1** so `VoxelGeneratorFlat` (which emits `voxel_type = 1`) renders as terrain without remapping; the rest load alphabetically. Deterministic across runs.

**Functions:**

| Function | Description |
|---|---|
| `get_def(block_id) -> BlockDef` / `get_def_by_index(index) -> BlockDef` | Def lookup either way. |
| `get_index(block_id) -> int` | Library index; air (`""`) → 0, unknown → -1. |
| `get_id(index: int) -> String` | Inverse: index → block_id (0 → `""`). |
| `has_id(block_id) -> bool` / `get_all_defs() -> Array` | Membership + full def list. |
| `get_voxel_library() -> VoxelBlockyLibrary` | The baked mesher library. |

---

## Subsystem: Player

Third-person controller, camera rig, Mode+State machine (GDD §4), inventory + equipment ownership.

### Files

| File | Type | Responsibility |
|---|---|---|
| `player.tscn` / `player.gd` | Scene/Script | CharacterBody3D + camera rig. Owns movement (WASD + sprint + jump with mid-air momentum preservation), inline Mode+State enums, build menu interaction (opens `build_menu.tscn` on a CanvasLayer), blueprint mode entry via menu selection + exit via `ui_cancel` (Esc). Exposes `get_camera()` for BuildController raycasts. Does NOT own combat resolution (delegates to Combat) or build UX (delegates to Build when in Blueprint mode). **TODO:** source movement stats from CharacterDef instead of `@export` vars. |
| `camera_rig.gd` | Script | Programmatically constructs its own SpringArm3D + Camera3D children in `_ready()`. Mouse look (yaw on rig, pitch on spring arm), zoom via spring length, collision on spring arm (layer 1). LMB/RMB reserved for item actions, not consumed here. |
| `player_state_machine.gd` | Script *(planned — not yet implemented)* | Mode + State logic (Normal/Blueprint × Idle/Walk/Sprint/Attack/Interact/Sleep/Dead). Currently inline in `player.gd`; will be extracted as Mode+State grow. |
| `../data/characters/player.tres` | Data | CharacterDef: HP, base move speed, sprint mult, Stamina drain rate, Breath costs. See Data Schema. |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `blueprint_mode_toggled(active)` | `player.gd` | BuildController, HUD | Yes | Enter Blueprint Mode |
| `player_died(context)` | `player.gd` *(planned — not yet emitted)* | GameState, HUD | Yes | Player Death / Respawn |
| `interact_started(target)` | `player.gd` *(planned — not yet emitted)* | (target's interact handler) | No | Loot / Door / Bed |

### Flow Trace: Enter Blueprint Mode

**Trigger:** Player presses `build_toggle` in Normal mode.

1. `player.gd` instantiates `res://ui/build_menu/build_menu.tscn` on a CanvasLayer (layer in `"ui_layer"` group, or a new one); releases cursor for menu interaction.
2. Player selects a buildable from the menu → menu emits its selection signal → `player.gd._on_buildable_selected(id)`: sets `mode = BLUEPRINT`; emits `blueprint_mode_toggled(true)` via EventBus; re-captures mouse.
3. HUD updates: shows build-mode controls hint, ghost preview enabled.
4. BuildController activates; routes LMB/RMB/mouse-wheel to placement/rotation.
5. Movement states still apply (player can walk while building).
6. Player presses `ui_cancel` (Esc) → `exit_blueprint_mode()`: sets `mode = NORMAL`; emits `blueprint_mode_toggled(false)`.
7. Dismissing the build menu without selecting → re-captures cursor; mode stays `NORMAL`.

**End state:** Build UX active; LMB/RMB repurposed; movement unaffected. Exit is via Esc, not B.

### Flow Trace: Sprint and Breath

> **Implementation status: planned, not yet built.** Sprint currently works as an unconditional Shift hold with no Breath gating or drain. The design below is the intended shape. Treat this as the spec to implement against, not a description of current code.

**Trigger:** Player holds Shift while moving (and Breath > 20%).

1. Player checks `breath_component.can_sprint()` (> 20%); if blocked, ignore Shift.
2. `player.gd` sets `state = SPRINT`; speed = base × sprint_multiplier (1.6×).
3. Player calls `breath_component.set_sprinting(true)`.
4. BreathComponent._process: `breath -= sprint_drain_rate (20) × delta`; emits `breath_changed`.
5. If `breath ≤ 0` → emit `sprint_available(false)`; Player forced to WALK.
6. Player Shift-release OR Breath empty → `state = WALK`; `set_sprinting(false)`.
7. BreathComponent._process (not sprinting): `breath += regen_rate (10) × delta` (capped 100); emits `breath_changed`.

**Other burst actions** (jump/melee/ranged) call `breath_component.spend(cost)` — blocked if `breath < cost`. Stamina drains independently via StaminaComponent (ambient always; ×2 while working).

**End state:** Sprint drains Breath, regenerates when not sprinting; Stamina unaffected by sprint.

### Flow Trace: Jump and Mid-Air Control

**Trigger:** Player presses jump while on floor.

1. `player.gd` sets `velocity.y = jump_force`; captures current horizontal wish-velocity into `_velocity_on_jump` and current speed into `_speed_on_jump`.
2. Mid-air: the frozen momentum is resolved per-axis (forward/back, strafe) against live camera directions via `_resolve_air_axis`. Keys can only *brake* the frozen momentum — they never re-project it, so camera rotation mid-air cannot curve movement.
3. Per-axis braking rules: both keys held = cancel; key held matching momentum direction = preserve; key held opposing momentum = nudge at `jump_move_speed`; neither held = snap stop (no coasting).
4. Speed scale at takeoff is frozen — releasing/pressing Shift mid-air does not change momentum scale.

**End state:** Jump preserves horizontal momentum from takeoff; player can brake but not steer mid-air.

### Class Reference

#### Class: Player

**Extends:** CharacterBody3D
**Script:** `player.gd`
**Description:** Player avatar. Owns movement, Mode+State transitions, input routing. Delegates combat to Combat subsystem, build UX to Build subsystem.
**Used by:** HUD (health bar), Combat (damage target), Build (placement source).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `walk_speed` | `float` | `[export default 3.5]` Ground move speed. **TODO:** source from CharacterDef. |
| `sprint_speed` | `float` | `[export default 7.0]` Sprint speed. **TODO:** source from CharacterDef. |
| `gravity` | `float` | `[export default 9.8]` Gravity acceleration. |
| `jump_force` | `float` | `[export default 5.0]` Vertical impulse on jump. |
| `jump_move_speed` | `float` | `[export default 0.5]` Mid-air nudge speed for axis braking. |
| `mode` | `Mode` enum | `NORMAL` or `BLUEPRINT`. |
| `state` | `State` enum | Movement/action state (`IDLE`, `WALK`, `SPRINT`, `ATTACK`, `INTERACT`, `SLEEP`, `DEAD`). Only `IDLE`/`WALK`/`SPRINT` are actively assigned at runtime; the rest are placeholders. |
| `character_def` | `CharacterDef` *(planned)* | Loaded resource (player.tres): max_hp, base_move_speed, sprint_multiplier, stamina_drain_rate, breath costs. |
| `breath_component` | `BreathComponent` *(planned)* | @onready ref; queried for sprint gating + burst-action spending. |
| `stamina_component` | `StaminaComponent` *(planned)* | @onready ref; queried for work/movement multipliers. |

**Functions:**

| Function | Description |
|---|---|
| `get_camera() -> Camera3D` | Public accessor; delegates to CameraRig. Used by BuildController for screen-center raycasts. |
| `exit_blueprint_mode() -> void` | One-way exit: sets `mode = NORMAL`; emits `blueprint_mode_toggled(false)`. Called on `ui_cancel` (Esc) in Blueprint mode. |
| `_open_build_menu() -> void` | Instantiates `build_menu.tscn` on a CanvasLayer; releases cursor for menu interaction. |
| `_on_buildable_selected(id: String) -> void` | Enters Blueprint mode on menu selection: sets `mode = BLUEPRINT`; emits `blueprint_mode_toggled(true)`. |
| `take_damage(amount: int, source: Node) -> void` *(planned)* | Forwards to Combat's damage resolver. |

---

## Subsystem: Build

Blueprint mode UX: cursor raycast, rotation state, ghost preview, validity check, commit — plus the global `BuildLibrary` catalog that everything reads from, and a `FurnitureLayer` for free-standing furniture. The controller is voxel-agnostic: all voxel coupling is behind the `IBlockGrid` adapter, and `voxel_tool` is never imported here.

**Two-kind placement model:** a single `BuildController` routes commit by the selected def's runtime kind (per the `BuildableDef` hierarchy in `data/`):
- **`BlockDef`** (voxel block: wood/scrap/stone/metal/reinforced) → `InstantPlacementStrategy` → `VoxelGridAdapter` → voxel grid.
- **everything else** — a plain `BuildableDef` (e.g. `pole`) or a `FurnitureDef` (e.g. `workbench`) → `FurnitureLayer`, which spawns a free-standing `Node3D` under the world's `FurnitureContainer`.

The def's shape drives routing everywhere: `BuildController._is_furniture(id)` is `def != null and not (def is BlockDef)`, the ghost uses the same test to pick a single-cell preview vs. a footprint-center preview, and `FurnitureLayer` reads `FurnitureDef.dimensions` for multi-cell validity + placement.

### Files

| File | Type | Responsibility |
|---|---|---|
| `build.tscn` / `build_controller.gd` | Scene/Script | Owns cursor raycast (screen-center, player-excluded), rotation state, ghost preview, validity, and commit. Does NOT know what commit does — it routes by def kind to the strategy (blocks) or the furniture layer (everything else). |
| `build_library.gd` | Autoload | Global catalog (`id → BuildableDef`) of everything buildable. Loads `data/blocks/`, `data/buildables/`, `data/furniture/`. Delegates "unlocked" to `RunProgress`; seeds defaults at startup + on `EventBus.run_started`. See Autoloads table. |
| `ghost_preview.gd` | Script | `MeshInstance3D` (translucent, validity-tinted green/red). Mesh is driven by the selected def's `mesh`; positioned each frame by the controller — single cell corner for blocks, footprint center for furniture. |
| `rotation_state.gd` | Script | Axis cycle (R: Z→X→Y) + 90° step wheel + the even-footprint 0.5m pivot rule (GDD §7.4). **STUB:** the 0.5m pivot is unimplemented (`get_yaw_degrees` returns a Z-axis yaw placeholder) and no input key is wired to `cycle_axis`/`cycle_step` yet — `step` is only read for furniture footprint swaps. |
| `i_block_grid.gd` | Script (interface) | Documentation-only contract: `get_block_at`, `set_block_at`, `remove_block_at`, `is_valid_placement`, `raycast_to_voxel`, `snap_transform`. Implementations duck-type; they do NOT extend it. |
| `i_placement_strategy.gd` | Script (interface) | Documentation-only contract: `commit(transform, rotation, item_id) -> bool`. Implementations duck-type; they do NOT extend it. |
| `instant_placement_strategy.gd` | Script (`RefCounted`) | MVP block strategy: resolves the cell from `transform.origin`, calls `VoxelGridAdapter.set_block_at`. Cost deduction deferred (TODO). |
| `blueprint_then_build_strategy.gd` | Script *(planned — not yet implemented)* | Post-MVP block strategy: spawns a blueprint ghost → registers a construction Job on the Job Board (colonist builds it over time). Will be the second `IPlacementStrategy` impl alongside `InstantPlacementStrategy`. |
| `voxel_grid_adapter.gd` | Script (`RefCounted`) | `IBlockGrid` impl wrapping `voxel/voxel_grid.gd`. Adds `is_valid_placement` + `snap_transform` + raycast `exclude` passthrough (for player-body exclusion). |
| `furniture_layer.gd` | Script (`RefCounted`) | Free-standing furniture layer — sibling of `VoxelGridAdapter` for non-block buildables. Spawns an `Node3D` (from `new_furniture_template.tscn`) under the world's `FurnitureContainer`; owns the anchor + footprint model (cell-box `dimensions`, yaw swaps x/z), overlap rejection, and removal-by-pointing-at-any-covered-cell. Emits `furniture_placed` / `furniture_removed` on EventBus. |
| `new_furniture_template.tscn` | Scene | Node template for spawned furniture: a root `Node3D` holding a `Mesh` `MeshInstance3D` (gets a runtime trimesh `StaticBody3D` on collision layer 1) + a `BuildBody` `StaticBody3D` with a footprint-sized `BoxShape3D` (collision layer 3). Rotated as a unit by yaw. |
| `../data/blocks/` | Data | `BlockDef` per block type (wood, scrap, stone, metal, reinforced, terrain). See Data Schema. |
| `../data/buildables/` | Data | Plain `BuildableDef` (player-placed objects not on the voxel grid — e.g. `pole`). |
| `../data/furniture/` | Data | `FurnitureDef` per furniture type (workbench, etc.); adds `dimensions: Vector3i`. Schema pending (C1). |

### Signals

Build placement has no same-scene signals — the controller calls strategies/layers directly, and the world-side reactions go through the global voxel/furniture emissions:

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `blueprint_mode_toggled(active)` | player subsystem | `BuildController` (activates/deactivates) | Yes | Enter/Exit Blueprint Mode |
| `buildable_selected(id)` | player subsystem (from build menu) | `BuildController` (sets `selected_id` + ghost mesh) | Yes | Select a Buildable |
| `block_placed(pos, block_id)` | `VoxelGrid` (via adapter) | colonists (pathfinding), raids (breach), Functional Rooms | No | Place Block |
| `furniture_placed(def_id, anchor)` | `FurnitureLayer` | Colony (Functional Rooms counter) | Yes | Place Furniture |
| `furniture_removed(def_id, anchor)` | `FurnitureLayer` | Colony (Functional Rooms counter) | Yes | Remove Furniture |

### Flow Trace: Place a voxel block (MVP → Instant)

**Trigger:** Player LMB-clicks (`build_place` action) in Blueprint mode with a `BlockDef` selected and valid placement.

1. `BuildController._try_commit` raycasts from screen center (player body excluded).
2. Target cell = struck voxel + face normal. Confirmed valid via `grid_adapter.is_valid_placement(cell)` (cell is air).
3. Routes to `_commit_block`: builds a `Transform3D` at the cell origin, calls `strategy.commit(transform, rotation_state, selected_id)`.
4. `InstantPlacementStrategy.commit` resolves the cell from the transform origin and calls `grid_adapter.set_block_at(cell, item_id)`.
5. Adapter delegates to `VoxelGrid.set_block_at` → emits `block_placed(pos, block_id)` (consumed by colonist pathfinding, raids, Functional Rooms).

**End state:** Block exists in the voxel grid; downstream listeners notified. Materials consumed (deferred — strategy TODO).

### Flow Trace: Place free-standing furniture

**Trigger:** Player LMB-clicks (`build_place`) in Blueprint mode with a non-block def selected (`BuildableDef` or `FurnitureDef`) and a free footprint.

1. `BuildController._try_commit` raycasts from screen center; cell = struck voxel + face normal.
2. Routes to `_commit_furniture` (the def is not a `BlockDef`).
3. `_is_footprint_free(anchor, def)`: for every cell in the (yaw-rotated) footprint, confirms `grid_adapter.is_valid_placement(cell)` AND `furniture_layer.has_at(cell)` is false. Rejects overlap with terrain, blocks, or existing furniture.
4. On success, `FurnitureLayer.spawn(def, anchor, rotation_state.step)`:
   - Instantiates `new_furniture_template.tscn`; assigns `def.mesh` to the `Mesh` node and builds a footprint-sized `BoxShape3D` collision on the `BuildBody` (layer 3) + a trimesh body (layer 1).
   - Positions at `FurnitureLayer.world_origin(anchor, dims, yaw)` (footprint center on XZ, anchor Y).
   - Registers every covered cell in `anchor_by_cell` (so removal by pointing at any covered cell resolves to the item) and the node in `node_by_anchor`.
   - Emits `furniture_placed(def.id, anchor)` on EventBus → Colony's Functional Rooms counter increments.

**End state:** Furniture node exists under `FurnitureContainer`; every covered cell reserved; Functional Rooms notified.

### Flow Trace: Remove (block or furniture)

**Trigger:** Player RMB-clicks (`build_remove`) in Blueprint mode.

1. `BuildController._try_remove` raycasts from screen center.
2. A block occupies the **struck voxel itself**; furniture occupies the **adjacent air cell** (it has no voxel collision — placement targeted the floor cell next to the struck surface). The controller tries both so RMB works on either kind:
   - If `grid_adapter.get_block_at(struck)` is non-empty → `grid_adapter.remove_block_at(struck)` → `block_destroyed`.
   - Else → `furniture_layer.remove_at(adjacent)` → resolves the anchor from any covered cell, frees the node, clears all its cells, emits `furniture_removed`.

### Class Reference

#### Class: BuildLibrary

**Extends:** Node (autoload)
**Script:** `build_library.gd`
**Description:** Global, read-only catalog of every buildable. Loads all three `BuildableDef` subclass folders into one polymorphic `id → BuildableDef` map. Holds no run-state — "what's unlocked" is delegated to `RunProgress`.
**Used by:** Build menu (lists available defs), `BuildController` (resolves `selected_id` → def for routing/ghost/commit), `InstantPlacementStrategy` (cost lookup, deferred).
**Lifecycle:** `_ready` loads the dirs, seeds `RunProgress` with `unlocked_by_default` defs, then connects `_seed_defaults` to `EventBus.run_started` (New Game: `RunProgress` was reset, defaults re-added from the in-memory catalog — no disk re-read).

**Functions:**

| Function | Description |
|---|---|
| `get_def(id: String) -> BuildableDef` | The def for `id`, or `null`. |
| `has_def(id: String) -> bool` | Catalog membership (independent of unlock state). |
| `is_unlocked(id: String) -> bool` | Thin pass-through to `RunProgress.is_unlocked`. |
| `get_unlocked() -> Array` | The defs currently available to the build menu. |
| `unlock(id: String) -> void` | Pass-through to `RunProgress.unlock` (items/skills/quests call this; callers talk to the catalog, not run-state internals). |

#### Class: BuildController

**Extends:** Node3D
**Script:** `build_controller.gd`
**Description:** Build-mode controller. Active only when Player.mode == BLUEPRINT. Owns cursor raycast (screen-center, player-body-excluded), rotation state, ghost preview, and commit routing. Delegates block commit to `InstantPlacementStrategy`, furniture commit to `FurnitureLayer`, and grid queries to `VoxelGridAdapter`.
**Used by:** World (runtime wiring after player exists), EventBus (`blueprint_mode_toggled`, `buildable_selected`).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `grid_adapter` | `VoxelGridAdapter` | Runtime-wired (RefCounted can't be `@export`'d). The active grid adapter. |
| `strategy` | `InstantPlacementStrategy` | Runtime-wired (same reason). The block placement strategy. |
| `furniture_layer` | `FurnitureLayer` | Runtime-wired. The free-standing furniture layer (non-block path). |
| `camera_path` | `NodePath` | `[export]` Path to the build camera; resolved in `_ready`, or via `set_camera()`. |
| `exclude_bodies` | `Array[PhysicsBody3D]` | Bodies to skip in the cursor raycast (the player capsule). Add via `add_exclude_body()`. |
| `rotation_state` | `RotationState` | Current axis + 90° step. |
| `selected_id` | `String` | The currently selected buildable id. Set by `EventBus.buildable_selected`; drives ghost mesh + commit routing. |

**Functions:**

| Function | Description |
|---|---|
| `set_active(active: bool) -> void` | Activates/deactivates the controller (called on `blueprint_mode_toggled`); shows/hides the ghost. |
| `set_camera(camera: Camera3D) -> void` | Runtime camera wiring (controller is a sibling of the player; can't use a relative path). |
| `add_exclude_body(body: PhysicsBody3D) -> void` | Adds a body to the raycast exclusion list. |

#### Class: VoxelGridAdapter

**Extends:** RefCounted
**Script:** `voxel_grid_adapter.gd`
**Description:** `IBlockGrid` implementation wrapping `voxel/voxel_grid.gd`. Keeps `BuildController` voxel-agnostic. Holds a `VoxelGrid` reference set at wiring time.
**Used by:** `BuildController` (raycast + validity queries), `InstantPlacementStrategy` (block set), `FurnitureLayer` (footprint validity queries).

**Functions:**

| Function | Description |
|---|---|
| `set_grid(grid: VoxelGrid) -> void` | Wiring. |
| `get_block_at(pos: Vector3i) -> String` | Block id at cell, or `""` for air. |
| `set_block_at(pos: Vector3i, block_id: String) -> void` | Delegates to `VoxelGrid`; emits `block_placed` there. |
| `remove_block_at(pos: Vector3i) -> void` | Delegates to `VoxelGrid`; emits `block_destroyed` there. |
| `is_valid_placement(pos: Vector3i) -> bool` | True if the cell is air. (TODO: ownership/footprint checks once multi-cell blocks exist.) |
| `raycast_to_voxel(origin, dir, max_dist, exclude: Array = []) -> Dictionary` | Physics raycast → `{position, normal, hit}`. `exclude` is an `Array[RID]` to ignore (player body). |
| `snap_transform(world_pos: Vector3) -> Vector3i` | Snap a world position to its containing cell. |

#### Class: FurnitureLayer

**Extends:** RefCounted
**Script:** `furniture_layer.gd`
**Description:** Free-standing furniture placement layer — sibling of `VoxelGridAdapter` for non-block buildables. Spawns an `Node3D` (from `new_furniture_template.tscn`) under the world's `FurnitureContainer`; owns the anchor + footprint model. Never touches `voxel_tool` — it asks `VoxelGridAdapter` whether candidate cells are free.
**Used by:** `BuildController` (non-block commit/remove), Colony (Functional Rooms, via `furniture_placed`/`furniture_removed`).

**Static helpers:**

| Function | Description |
|---|---|
| `footprint_cells(dimensions: Vector3i, yaw_quarters: int) -> Array[Vector3i]` | Cell offsets an item covers (yaw swaps width/depth; height unchanged). |
| `dimensions_of(def: BuildableDef) -> Vector3i` | Effective cell-box (def's `dimensions` if `FurnitureDef`, else `1×1×1`). |
| `world_origin(anchor, dimensions, yaw_quarters) -> Vector3` | World-space spawn origin: footprint center on XZ, anchor Y. |

**Functions:**

| Function | Description |
|---|---|
| `set_container(container: Node3D) -> void` | Wiring: where spawned nodes parent. |
| `spawn(def: BuildableDef, anchor: Vector3i, yaw_quarters: int) -> Node3D` | Place an item; returns the node or `null` if unwired/overlapping/no mesh. Emits `furniture_placed(def.id, anchor)`. |
| `remove_at(cell: Vector3i) -> bool` | Remove the item covering `cell` (any covered cell resolves to its anchor). Emits `furniture_removed`. |
| `has_at(cell: Vector3i) -> bool` | Whether any item covers `cell`. |

---

## Subsystem: Functional Rooms

Tracks which functional-furniture types are placed in the colony and how many of each. Gates capability unlocks (world map, crafting, smelting, etc.) and feeds the raid visibility bonus. GDD §7.8.

> **Implementation status: planned, not yet built.** The design below is the intended shape, but **none of it exists in `colony.gd` yet** — there is no `functional_counts` state, no `_on_block_placed` / `_on_block_destroyed` listeners, and no `count_functional_furniture()` / `count_of()` / `has_functional()` surface. The `data/furniture/` schema (`is_functional` + `functional_area`) is also still pending (C1). Treat this section as the spec to implement against, not a description of current code. The pieces it depends on *do* exist: `VoxelGrid` emits `block_placed` / `block_destroyed`, and `FurnitureLayer` emits `furniture_placed` / `furniture_removed` (the more likely source once furniture is non-block — see note below).

**Design notes:**
- **No room detection** — there's no bounding-box or enclosure check. "Functional area unlocked" means *at least one of the furniture type exists in the colony*, placed anywhere.
- **"Functional furniture" = the 7 area-defining types only** (Clinic Bed, Workbench, Forge, Command Desk, Vehicle Lift, Colonist Bed, Growing Trough). Storage crates, watchtowers, spike traps, lamps do NOT count.
- **Counts live directly on the Colony autoload** (not a separate child). It's just 7 integers — too small to justify a 5th Colony child. Colony exposes the query surface; ThreatModel and UI read from it.
- **Signal source — open question.** The doc previously assumed Colony subscribes to `VoxelGrid.block_placed` / `block_destroyed`. With the two-kind placement model now landed (Build subsystem), functional furniture is a `FurnitureDef` placed via `FurnitureLayer`, which emits `furniture_placed` / `furniture_removed` on EventBus — not `block_placed`. Decide at implementation time whether to count from the furniture emissions, the voxel emissions (only relevant if a functional type is ever a `BlockDef`), or both.

### Files

| File | Type | Responsibility |
|---|---|---|
| *(no separate script — functionality folded into Colony autoload)* | — | Colony tracks `functional_counts: Dictionary[String, int]` directly; the placement/destroy listeners + query methods are Colony methods. Documented here because the *feature* is distinct even though the code lives on Colony. |
| `../data/furniture/` | Data | FurnitureDef per type — includes `is_functional: bool` flag + `functional_area: String` so the registry knows which placements to count. Schema pending (C1). |

### Signals

*(No new signals — Functional Rooms subscribes to VoxelGrid's `block_placed`/`block_destroyed` and exposes query methods. The consumer-side reaction is pull-based: ThreatModel and UI call `Colony.count_functional_furniture()` when they need it.)*

### Flow Trace: Placing functional furniture updates the registry

**Trigger:** Player (or colonist via construction Job) places a furniture block via the Build subsystem; VoxelGrid emits `block_placed(pos, block_id)`.

1. Colony listens for `block_placed`.
2. Looks up the block's FurnitureDef (from `data/furniture/`).
3. If `def.is_functional == true`: increment `functional_counts[def.functional_area]`.
4. (No emission — consumers pull on demand. UI can poll on its refresh tick; ThreatModel pulls at raid-start.)

**End state:** Colony's functional count for that area incremented; capability unlocked if it was the first; visibility bonus increased (+3 to all edges, applied at next raid).

### Flow Trace: Raid visibility reads the functional count

**Trigger:** RaidScheduler computes a new raid (on `day_rolled_over`, if colony ≥ 3 colonists).

1. ThreatModel needs the colony's visibility bonus.
2. Calls `Colony.count_functional_furniture()` → sums all 7 counts (per-item: 3 Workbenches + 1 Clinic Bed = 4).
3. Applies `+3 per item to all edges equally` → bumps each edge weight by `(count × 3)`.
4. Proceeds with weighted-random edge selection per the normal threat-direction flow.

**End state:** Raid threat edges reflect the colony's current functional-furniture footprint.

### Class Reference

*(Planned — methods/state live on the Colony autoload. None of this is implemented yet; documented here because the feature is distinct even though the code will live on Colony.)*

#### Colony methods (Functional Rooms surface)

| Function | Description |
|---|---|
| `count_functional_furniture() -> int` | Sum of all 7 functional-furniture counts (per-item). Used by ThreatModel for the visibility bonus. |
| `count_of(type: String) -> int` | Count of a specific functional type (e.g. `"workbench"`). |
| `has_functional(type: String) -> bool` | True if at least one of `type` is placed. Used by UI for capability-unlock gating (e.g. world-map tab greyed out until `has_functional("command_desk")`). |
| `_on_block_placed(pos: Vector3i, block_id: String) -> void` | VoxelGrid signal listener; increments `functional_counts` if the block is functional furniture. |
| `_on_block_destroyed(pos: Vector3i) -> void` | VoxelGrid signal listener; decrements the relevant counter. |

**State on Colony:**

| Property | Type | Description |
|---|---|---|
| `functional_counts` | `Dictionary[String, int]` | 7 entries keyed by functional_area (`"command"`, `"medical"`, `"crafting"`, `"smelting"`, `"vehicle"`, `"rest"`, `"farming"`). Saved with Colony state. |

---

## Subsystem: Colonists

Colonist entities, roster (in Colony autoload), Job Board, labor AI, raid stances. GDD §6.

### Files

| File | Type | Responsibility |
|---|---|---|
| `colonist_base.gd` | Script | Base for all colonists. Holds HP, skills, labor priorities, raid stance, current Job. Does NOT own job discovery (Job Board does). |
| `colonist.tscn` | Scene | Capsule mesh + CollisionShape + components. |
| `../autoloads/colony.gd` | Autoload | Roster + Job Board. Cross-scene (colonists persist base↔POI). |
| `job_board.gd` | Script (on Colony) | Job registry; claim/unclaim/fail logic. Early-MVP: log+skip+auto-remove-3. Late-MVP: blocked-state + Retry. |
| `colonist_ai.gd` | Script | Idle → query Job Board → claim → path (A*) → work → release. Does NOT own pathfinding (uses A* on voxel grid). |
| `colonist_combat.gd` | Script | Reactive engagement logic (hold position; fire missile if in range; melee if adjacent). GDD §6.7. |
| `../data/labors/` | Data | Labor definitions (Construction, Crafting, Smelting, Mechanics, Hauling; Repair/Farming/Cooking post-MVP). Crafting + Smelting Labors claim Jobs produced by the Crafting subsystem's stations. |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist_base.gd` | Colony, HUD, Memorial | Yes | Colonist Death |
| `job_claimed(job_id, colonist_id)` | `job_board.gd` | (internal) | No | Colonist Works a Job |
| `job_failed(job_id, reason)` | `job_board.gd` | Job Log UI | No | Job Failure Handling |
| `job_logged(entry)` | `job_board.gd` | Job Log UI (when open) | Yes | Job Failure Handling |

### Flow Trace: Colonist works a job (claim → path → work)

**Trigger:** Colonist becomes idle.

1. `colonist_ai.gd` queries `JobBoard.get_best_job_for(colonist)` — highest-priority Labor with an available Job the colonist meets the L1 skill gate for (`skill_set.meets_requirement`), then nearest by proximity.
2. JobBoard atomically claims the Job (returns job or null).
3. Colonist A* paths to job location (via voxel grid).
4. On arrival, each work tick: effective rate = `job.base_rate × skill_set.get_multiplier(labor) × stamina_component.get_work_multiplier()`. Marks `stamina_component.set_working(true)` while active.
5. On completion → `skill_set.record_use(skill_id)` (grants skill progress); `stamina_component.set_working(false)`; `JobBoard.complete(job_id)`; colonist returns to step 1.

**End state:** Job complete at combined skill × Stamina rate; skill progressed; Stamina burned at ×2; colonist seeks next.

### Flow Trace: Job failure handling (early-MVP)

**Trigger:** Colonist can't finish a job (no materials / blocked path / target destroyed).

1. `colonist_ai.gd` calls `JobBoard.fail(job_id, reason)`.
2. JobBoard logs entry; emits `job_logged` via EventBus.
3. JobBoard increments job's failure_count.
4. If failure_count >= 3 → auto-remove from board (blueprint stays placed if construction).
5. Colonist queries next enabled Job.

**End state:** Failed job logged + skipped; colonist continues; no player action required.

### Class Reference

#### Class: Colony

**Extends:** Node
**Script:** `autoloads/colony.gd`
**Description:** The colony roster and Job Board. Cross-scene because colonists persist during expeditions. Owns colonist lifecycle and job discovery.
**Used by:** HUD (roster UI), Colony Management screen, Combat (damage targets), Raids (stance execution).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonists` | `Array[ColonistBase]` | Active colonists (max 5 in MVP). |
| `job_board` | `JobBoard` | The Job Board instance. |

**Functions:**

| Function | Description |
|---|---|
| `add_colonist(colonist: ColonistBase) -> void` | Recruits a colonist (random event / radio). |
| `remove_colonist(colonist_id: String) -> void` | On death or departure. |

#### Class: ColonistBase

**Extends:** CharacterBody3D
**Script:** `colonist_base.gd`
**Description:** Base class for all colonists. Holds stats, skills, labor priorities, raid stance, current Job.
**Used by:** Colony (roster), Combat (target), Colonist Management screen.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonist_id` | `String` | Unique ID. |
| `display_name` | `String` | Shown in UI. |
| `max_hp` | `int` | [export] 100 baseline (companion +20%). |
| `labor_priorities` | `Dictionary` | Labor → 0–5 priority. |
| `raid_stance` | `RaidStance` enum | Fight / Fight Post / Shelter. |
| `skill_set` | `SkillSet` | @onready ref; holds this colonist's 6 skills + progress. See Skills subsystem. |
| `stamina_component` | `StaminaComponent` | @onready ref; work/move multipliers + collapse state. See Energy subsystem. |

---

## Subsystem: Skills

Per-entity skill progression (L1–L5, use-based). Determines work-speed multiplier; gates regular jobs at L1. GDD §6.3. Lives on both Player and Colonists via a reusable `SkillSet` component. The Player screen's Skills *tab* is post-MVP (the data progresses in MVP; the UI to view it is deferred).

**Work-speed combination (locked):** effective work rate = `base_rate × skill_multiplier × stamina_multiplier`. `SkillSet.get_multiplier(labor)` returns the skill factor (1.0 at L1 → 2.0 at L5); `StaminaComponent.get_work_multiplier()` returns the Stamina factor (1.0 fresh → 0.6 at collapse). The Job Board / colonist AI multiplies them. See Flow Trace below.

### Files

| File | Type | Responsibility |
|---|---|---|
| `skill_set.gd` | Script (component) | Holds the 6 skills + their current level + progress for one entity. Owns use-based leveling (increments progress on successful completions; levels up at thresholds). Exposes `get_multiplier(labor)`. Does NOT own global skill definitions or curves (those are data). |
| `../data/skills/skills.tres` | Data | Global SkillDef list (6 skills) + use-curves + per-level multipliers. See Data Schema. |

*The component script lives in `skills/` (its own folder) rather than `combat/` because it's consumed by Colonists + Player + UI, not combat-specific. Same pattern rationale as the character-stat components — see Tech Debt on a possible future `core/components/` home.*

### Signals

All same-scene (No EventBus) — skills are per-entity, read locally.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `skill_progressed(skill_id, progress)` | `skill_set.gd` | HUD (skill bar, future Skills tab) | No | Skill Gains Progress |
| `skill_leveled_up(skill_id, new_level)` | `skill_set.gd` | HUD (notification), Day Summary (skill gains) | No | Skill Levels Up |

### Flow Trace: Skill gains progress on a successful job completion

**Trigger:** A colonist (or player) successfully completes a skilled Job (craft/build/smelt/treat/repair) — fired by the Job Board or the labor AI on success.

1. Caller invokes `skill_set.record_use(skill_id)` on the entity.
2. `SkillSet` increments the skill's progress counter.
3. Emits `skill_progressed(skill_id, progress)` (for future Skills-tab UI).
4. If progress crosses the next level's threshold (from `skills.tres` use-curve): increment level, emit `skill_leveled_up(skill_id, new_level)`.
5. HUD shows a brief level-up notification; Day Summary logs the gain.

**End state:** Skill progress updated; level may have increased; work-speed multiplier for that Labor is now higher.

### Flow Trace: Work-speed multiplier resolves a Job tick

**Trigger:** A colonist is actively working a Job (per Job Board flow); each work tick applies progress.

1. Colonist AI reads `skill_set.get_multiplier(job.labor)` → returns skill factor (1.0–2.0 by level).
2. Colonist AI reads `stamina_component.get_work_multiplier()` → returns Stamina factor (1.0–0.6 by band).
3. Effective rate = `job.base_rate × skill_factor × stamina_factor`.
4. Applies that rate to the Job's progress (build HP, craft completion, etc.).
5. On Job completion → triggers `skill_set.record_use(skill_id)` (Flow Trace above).

**End state:** Job progresses at the combined skill × Stamina rate; completion grants skill progress.

### Class Reference

#### Class: SkillSet

**Extends:** Node
**Script:** `skill_set.gd` (in `skills/`)
**Description:** Per-entity skill progression. Holds level + progress for each of the 6 skills. Use-based leveling on successful job completions. Exposes work-speed multiplier per Labor.
**Used by:** Colonist AI (work-speed calc), Player (same), Job Board (L1 gating check), HUD (future Skills tab + notifications), Day Summary (skill-gain log).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `skills` | `Dictionary[String, SkillState]` | Per-skill state. Keyed by skill_id (`"medical"`, `"mechanical"`, etc.). `SkillState = { level: int, progress: int }`. |
| `skill_defs` | `SkillDefList` | Loaded from `data/skills/skills.tres` (shared) — use-curves + multipliers. |

**Signals:**

| Signal | Description |
|---|---|
| `skill_progressed(skill_id: String, progress: int)` | For UI (future Skills tab). Emitted on every `record_use`. |
| `skill_leveled_up(skill_id: String, new_level: int)` | For UI notification + Day Summary log. Emitted on threshold cross. |

**Functions:**

| Function | Description |
|---|---|
| `record_use(skill_id: String) -> void` | Increments progress; levels up if threshold crossed. Called by Job Board / labor AI on successful job completion. |
| `get_level(skill_id: String) -> int` | Returns 1–5. |
| `get_multiplier(labor: String) -> float` | Returns the work-speed multiplier for a Labor (maps Labor → skill_id → level → multiplier from `skills.tres`). L1=1.0 → L5=2.0. |
| `meets_requirement(skill_id: String, min_level: int) -> bool` | Gates regular jobs at L1; specialist gates (post-MVP) at higher levels. |

---

## Subsystem: Combat

Damage resolution (Durability-before-HP, GDD §6.11), weapons, enemy base + Brawler/Shooter archetypes.

### Files

| File | Type | Responsibility |
|---|---|---|
| `damage_resolver.gd` | Script | Static/class: applies damage per §6.11. AP-equivalent (Durability) depletes first, overflow to HP. Used by player, colonists, enemies. |
| `health_component.gd` | Script | Reusable component (Node): HP + Durability + death signal. Attached to player, colonists, enemies. |
| `breath_component.gd` | Script | Reusable component (Node): Breath pool (burst energy). Attached to player, colonists, enemies. See Energy subsystem. |
| `stamina_component.gd` | Script | Reusable component (Node): Stamina pool (daily energy). Attached to player + colonists (enemies future). See Energy subsystem. |
| `weapon_base.gd` | Script | Base for weapons; defines damage/rate/range. |
| `enemy_base.gd` | Script | Base for all enemies. Owns state machine hook, navigation. Does NOT own damage rules (uses DamageResolver). |
| `brawler.gd` / `brawler.tscn` | Script/Scene | Brawler archetype: Chase state, 1.5m melee, 5s LOS timeout. |
| `shooter.gd` / `shooter.tscn` | Script/Scene | Shooter archetype: Reposition state, 10m holding, melee fallback. |
| `../data/characters/` | Data | CharacterDef per type (player.tres, colonist.tres, companion.tres, brawler.tres, shooter.tres). Supersedes the retired `data/player_stats.tres` and `data/enemies/`. |
| `../data/weapons/` | Data | Weapon stats (Knife, Pistol; Club/Bow post-MVP). |
| `../data/armor/` | Data | Armor Durability per piece per tier (Cloth/Leather/Scrap). |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `entity_died(entity)` | `health_component.gd` | owner script (player/colonist/enemy) | No | Damage Resolution |
| `player_died(context)` | `player.gd` (on death signal) | GameState, HUD | Yes | Player Death |
| `colonist_died(colonist_id)` | `colonist_base.gd` (on death) | Colony, HUD, Memorial | Yes | Colonist Death |

### Flow Trace: Damage resolution (Durability-before-HP)

**Trigger:** Any entity takes a hit (melee swing connects, ranged shot hits).

1. Attacker calls `target.health_component.take_damage(amount, source)`.
2. `health_component` calls `DamageResolver.apply(amount, current_durability, current_hp)`.
3. DamageResolver: if Durability > 0, reduce Durability first; overflow to HP.
4. Returns new `{durability, hp}`; health_component updates.
5. If hp ≤ 0 → emit `entity_died`.

**End state:** Durability/HP updated; death signal if applicable.

### Flow Trace: Brawler engages player

**Trigger:** Player enters Brawler's 10m detection radius with LOS.

1. Brawler transitions Idle → Chase; acquires player as target.
2. NavigationAgent paths toward player.
3. Every 0.5s, re-targets nearest reachable colonist/player.
4. On reaching 1.5m → Chase → Attack.
5. Attack windup 0.4s → applies 25 damage to player via `health_component.take_damage`.
6. If player leaves 1.5m → back to Chase; if LOS lost 5s → Idle.

**End state:** Brawler in melee combat; player taking damage.

### Class Reference

#### Class: DamageResolver

**Extends:** RefCounted (static class)
**Script:** `damage_resolver.gd`
**Description:** Pure damage math per GDD §6.11. No state, no signals — just computes new Durability/HP from inputs.
**Used by:** Combat (player/colonist/enemy damage), UI (display).

**Functions:**

| Function | Description |
|---|---|
| `static apply(damage: int, durability: int, hp: int) -> Dictionary` | Returns `{durability, hp, died: bool}`. Durability depletes first, overflow to HP. |

#### Class: HealthComponent

**Extends:** Node
**Script:** `health_component.gd`
**Description:** Reusable component attached to any damageable entity. Holds HP + Durability; delegates math to DamageResolver. One of three paired character-stat components on the player/colonists (with BreathComponent + StaminaComponent); enemies get HealthComponent + BreathComponent only.
**Used by:** Player, Colonists, Enemies.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `max_hp` | `int` | [export] 200 (player) / 100 (colonist) / varies (enemy). |
| `max_durability` | `int` | Derived at runtime from the character's `Equipment` component (`equipment.get_total_durability()`); recalculated on equip/unequip. 0 if no armor equipped. |
| `hp` / `durability` | `int` | Current values. |

**Signals:**

| Signal | Description |
|---|---|
| `hp_changed(new_hp)` | For UI health bars. |
| `durability_changed(new_durability)` | For UI armor bars. |
| `entity_died()` | HP hit 0. |

---

## Subsystem: Equipment & Loadouts

Per-character equipped gear + named loadout templates that auto-equip on raid/expedition and auto-return to storage on return. GDD §17 Equipment + §12 Loadout Template editor.

**Design notes:**
- **`Equipment` is a component on each character** (8 slots: 6 armor + melee + ranged). Pairs with HealthComponent — HealthComponent's `max_durability` is the sum of equipped armor Durability values.
- **`LoadoutTemplate` = slot → item_def_id mapping** (abstract, not concrete instances). Equipping resolves the template to concrete items pulled from storage at equip time. Handles "discovered gear" + "nearest unclaimed" rules cleanly.
- **Templates live in `data/loadouts/`** (player-created, saved per run). The *catalog* of equippable item_defs lives in `data/items/` (already specced) + `data/weapons/` + `data/armor/` (C9 schemas pending).
- **"Discovered gear" lives on Colony** (run-state, persists + saves, like Memorial/KeyItemPool): tracks which item_def_ids the colony has possessed at least once. Gates the loadout-slot picker UI.
- **Auto-equip/unequip subscribes to existing EventBus signals** (`raid_started`, `expedition_started`, `raid_ended`, `expedition_ended`) — no new trigger signals.
- Player character's `Gear` tab in the Player screen uses the same Equipment component (manual equip, no loadout template needed for the player in MVP).

### Files

| File | Type | Responsibility |
|---|---|---|
| `equipment.gd` | Script (component) | Per-character equipped gear (8 slots). Holds concrete item references; exposes `get_total_durability()` for HealthComponent. Does NOT own loadout templates (those are data + Colony). |
| `loadout_manager.gd` | Script (on Colony autoload) | Holds player-created templates; resolves + executes auto-equip/unequip on raid/expedition signals. Owns the "nearest unclaimed item" resolution. |
| `discovered_gear.gd` | Script (on Colony autoload) | Tracks item_def_ids the colony has ever possessed (once per run). Gates the loadout-slot picker. Subscribes to Inventory `item_picked_up`. |
| `../data/loadouts/` | Data | Player-created templates, saved per run. See Data Schema. |
| `../data/armor/` | Data | Armor defs per slot per tier (Durability values from GDD §17). Schema pending (C9). |
| `../data/weapons/` | Data | Weapon defs (Knife, Pistol; Club/Bow post-MVP). Schema pending (C9). |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `equip_completed(character, slot, item_id)` | `equipment.gd` | HealthComponent (recalc max_durability), HUD | No | Equip from Loadout |
| `unequip_completed(character, slot)` | `equipment.gd` | HealthComponent (recalc), HUD | No | Unequip on Return |

*(Auto-equip triggers come from existing `raid_started` / `expedition_started` / `raid_ended` / `expedition_ended` signals on EventBus — Equipment subscribes, doesn't emit new triggers.)*

### Flow Trace: Player creates a loadout template + assigns it

**Trigger:** Player opens Colony screen → Loadouts tab → clicks New.

1. UI creates a blank `LoadoutTemplate` (random default name, all slots empty).
2. Player names it; clicks each slot to assign:
   - Slot picker queries `Colony.discovered_gear.get_discovered_for_slot(slot)` → filters to item_defs valid for that slot + discovered this run.
   - Player picks one (or "auto-assign" → MVP: nearest unclaimed item for that slot in storage).
3. Player saves the template → written to `Colony.loadout_manager.templates` (and to `data/loadouts/` on save).
4. Player assigns the template to a colonist via the per-colonist dropdown.

**End state:** Named template exists with slot→item_def_id mappings; assigned to one or more colonists.

### Flow Trace: Colonist auto-equips loadout on raid start

**Trigger:** EventBus emits `raid_started(raid_data)`.

1. `LoadoutManager` (on Colony) listens → for each colonist with an assigned template:
2. For each slot in the template: resolve `item_def_id` to a concrete item from colony storage (nearest unclaimed of that type).
3. Move item: storage → `colonist.equipment.equip(slot, item)`.
4. `Equipment` emits `equip_completed` → HealthComponent recalculates `max_durability` (sum of equipped armor).
5. If no matching item in storage: slot stays empty (partial equip); Job Log notes the gap.

**End state:** Colonist equipped per template (best-effort); Durability updated; ready for raid.

### Flow Trace: Colonist returns equipment to storage on return

**Trigger:** EventBus emits `raid_ended(outcome)` or `expedition_ended(result)`.

1. `LoadoutManager` listens → for each returning colonist:
2. For each equipped slot: move item → `colonist.equipment.unequip(slot)` → back to colony storage (via Inventory add flow).
3. `Equipment` emits `unequip_completed` → HealthComponent recalculates `max_durability` (back to 0 if no permanent armor).
4. Items now available in storage for reassignment or repair.

**End state:** Colonist bare; equipment in storage; Durability reset.

### Class Reference

#### Class: Equipment

**Extends:** Node (component on Player + each Colonist)
**Script:** `equipment.gd` (in `equipment/`)
**Description:** Per-character equipped gear (8 slots). Holds concrete item references; HealthComponent reads total Durability from it.
**Used by:** HealthComponent (max_durability calc), Combat (weapon damage/ammo), HUD (gear display), LoadoutManager (equip/unequip target).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `slots` | `Dictionary[String, Item]` | 8 entries keyed by slot id (`"armor_head"`, `"armor_body"`, ..., `"melee"`, `"ranged"`). Values are concrete `Item` refs or null. |

**Signals:**

| Signal | Description |
|---|---|
| `equip_completed(character, slot, item_id)` | For HealthComponent recalc + HUD refresh. |
| `unequip_completed(character, slot)` | For HealthComponent recalc + HUD refresh. |

**Functions:**

| Function | Description |
|---|---|
| `equip(slot: String, item: Item) -> void` | Places item in slot; emits `equip_completed`. |
| `unequip(slot: String) -> Item` | Removes + returns item; emits `unequip_completed`. |
| `get_total_durability() -> int` | Sum of equipped armor Durability values. Called by HealthComponent. |
| `get_weapon_damage() -> int` | Melee weapon's fixed damage (or 0 if none). |
| `get_active_ranged() -> Item` | The ranged-weapon Item (for ammo consumption). |

#### Class: LoadoutManager

**Extends:** Node (child of Colony autoload)
**Script:** `loadout_manager.gd` (in `equipment/`)
**Description:** Holds player-created loadout templates; resolves + executes auto-equip/unequip on raid/expedition signals. Owns the "nearest unclaimed item" resolution.
**Used by:** UI (Loadouts tab — create/assign/delete), Colony (subscribes raid/expedition signals).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `templates` | `Array[LoadoutTemplate]` | Player-created templates (saved per run in `data/loadouts/`). |
| `assignments` | `Dictionary[String, String]` | colonist_id → template_id. |

**Functions:**

| Function | Description |
|---|---|
| `create_template(name: String) -> String` | Returns new template_id. |
| `delete_template(template_id: String) -> void` | Also clears any assignments referencing it. |
| `assign(colonist_id: String, template_id: String) -> void` | Per-colonist assignment. |
| `auto_equip_for_raid() -> void` | Called on `raid_started`; resolves + equips all assigned colonists. |
| `auto_unequip_on_return() -> void` | Called on `raid_ended`/`expedition_ended`; returns all equipped to storage. |

#### Class: DiscoveredGear

**Extends:** Node (child of Colony autoload)
**Script:** `discovered_gear.gd` (in `equipment/`)
**Description:** Once-per-run tracking of item_def_ids the colony has possessed. Gates the loadout-slot picker. Subscribes to Inventory signals.
**Used by:** UI (Loadouts slot picker), LoadoutManager (auto-equip candidates).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `discovered` | `Array[String]` | item_def_ids ever possessed this run. Saved with Colony. |

**Functions:**

| Function | Description |
|---|---|
| `mark_discovered(item_def_id: String) -> void` | Called on item pickup; idempotent. |
| `get_discovered_for_slot(slot: String) -> Array[String]` | Filters discovered item_defs valid for the slot (for the picker UI). |

---

## Subsystem: Energy

Two personal-energy pools on each character, both framed as depleting resources (100% fresh → 0% empty). Split from the original single "Fatigue" pool so burst costs (sprint/jump/melee/ranged) and daily grind (time + work) evolve independently. See GDD §17 Energy subsystem for the full mechanic spec.

**Entity attachment matrix** (key architectural fact — component presence IS capability):

| Entity | BreathComponent | StaminaComponent | MVP usage |
|---|---|---|---|
| Player | ✅ | ✅ | Sprint/jump/melee/ranged (Breath); daily collapse (Stamina) |
| Colonist | ✅ | ✅ | Breath unused in MVP (future special actions); daily collapse (Stamina) |
| Enemy (Brawler/Shooter) | ✅ | ❌ | Breath unused in MVP (future windup/heavy attacks); Stamina is a future addition |

BreathComponent is attached to enemies now so future Breath-consuming features don't require architectural change.

### Files

| File | Type | Responsibility |
|---|---|---|
| `../combat/breath_component.gd` | Script (component) | Breath pool (burst energy). Self-ticking in `_process`. Owns sprint drain + jump/melee/ranged costs + regen. Does NOT cause collapse (that's Stamina). |
| `../combat/stamina_component.gd` | Script (component) | Stamina pool (daily energy). Self-ticking in `_process`. Owns ambient drain + work multiplier + bands + collapse. Does NOT gate burst actions (that's Breath). |
| `../data/energy_config.tres` | Data | Global Stamina thresholds/floors + work multiplier. See Data Schema. |
| character defs (in `../data/characters/`) | Data | Per-character Stamina drain rate + Breath costs. See Data Schema. |

*Component scripts live in `combat/` alongside HealthComponent (all three are paired character-stat components). See Tech Debt on a possible future `core/components/` home.*

### Signals

All same-scene (No EventBus) — Energy is per-entity, consumed locally by the owning character + HUD.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `breath_changed(value)` | `breath_component.gd` | HUD (Breath bar) | No | Sprint/Burst drain |
| `sprint_available(available)` | `breath_component.gd` | Player (sprint gate) | No | Sprint/Burst drain |
| `stamina_changed(value)` | `stamina_component.gd` | HUD (Stamina bar) | No | Daily Stamina drain |
| `stamina_band_changed(band)` | `stamina_component.gd` | HUD (status icon), Player (move floor), Colonist AI (work floor / collapse) | No | Daily Stamina drain, Active work, Sleep reset |

### Flow Trace: Sprint and burst actions drain Breath, regenerates when idle

**Trigger:** Player sprints, jumps, melee-swings, or fires a ranged weapon.

1. Player queries `breath_component.can_sprint()` before entering SPRINT state (requires breath > 20%).
2. On SPRINT entry: Player calls `breath_component.set_sprinting(true)`.
3. BreathComponent._process: `breath -= sprint_drain_rate × delta`; emits `breath_changed`.
4. If `breath ≤ 0`: emit `sprint_available(false)` → Player forced to WALK.
5. Other burst actions call `breath_component.spend(cost)` — returns false (blocked) if `breath < cost`.
6. When not sprinting (or not spending): `breath += regen_rate × delta` (capped 100); emits `breath_changed`.

**End state:** Breath cycles between drain (burst) and regen (idle). Never causes collapse. Player-only in MVP (colonists/enemies don't sprint in MVP, but BreathComponent is attached for future use).

### Flow Trace: Daily Stamina drain + collapse at 0%

**Trigger:** Time passes (always, while awake). Applies to Player + Colonists.

1. StaminaComponent._process: `stamina -= drain_rate × delta` (drain_rate from character def).
2. Emits `stamina_changed`.
3. On crossing thresholds, emits `stamina_band_changed(band)`:
   - < 45% → Tired band → work-speed penalty active (floor 60% at collapse).
   - < 25% → Exhausted band → movement penalty also active (floor 40% at collapse).
   - = 0% → Collapsed band → owner enters collapse state (Player forced IDLE; colonist AI hard-stopped).
4. Listeners react: HUD updates status icon; Player applies movement floor; colonist_ai halts job-seeking.

**End state:** Stamina depletes over the day; character collapses at 0% until sleep. Sleep is the only recovery (Player action — collapsed colonists simply stay down until the next day).

### Flow Trace: Active work doubles Stamina drain

**Trigger:** Player or Colonist starts/stops an active work Job (craft/build/smelt/haul).

1. Colonist AI (or Player, for manual build) calls `stamina_component.set_working(true)` on Job start.
2. StaminaComponent applies `work_multiplier (×2)` to its drain in `_process`.
3. On Job completion/failure: `set_working(false)` → drain returns to ambient.

**End state:** Working burns the daily budget faster; choosing to work is choosing to spend Stamina. Interleaves with ambient drain (always-on) and the collapse rule.

### Flow Trace: Sleep resets Stamina to 100%

**Trigger:** Player interacts with bed (E) at base → triggers Core's Sleep→Day Summary flow.

1. Core's Sleep flow calls `time_system.advance_to_midnight()` → `day_rolled_over`.
2. For each entity with StaminaComponent (Player + all colonists): `stamina_component.reset()` → sets `stamina = 100`, emits `stamina_changed` + `stamina_band_changed(FRESH)`.
3. BreathComponent.reset() also called (top up Breath to 100 for consistency).
4. Collapse state clears; colonist AI resumes job-seeking next morning.

**End state:** All characters at full Stamina + Breath at start of new day. Collapse lifted.

### Class Reference

#### Class: BreathComponent

**Extends:** Node
**Script:** `breath_component.gd` (in `combat/`)
**Description:** Short-term burst energy pool. Self-ticking. Drains on sprint/jump/melee/ranged; regenerates when idle. Gates sprinting. Does NOT cause collapse.
**Used by:** Player (sprint gating + burst-action spending), Colonists (future), Enemies (future). HUD (Breath bar).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `breath` | `float` | Current value, 0–100. |
| `max_breath` | `float` | [export] 100. |
| `sprint_drain_rate` | `float` | [export] 20/sec while sprinting. |
| `regen_rate` | `float` | [export] 10/sec when not exerting. |
| `jump_cost` / `melee_cost` / `ranged_cost` | `float` | [export] 10 / 5 / 2 per action. |
| `sprint_gate` | `float` | [export] 20 — below this, sprint is blocked. |

**Signals:**

| Signal | Description |
|---|---|
| `breath_changed(value: float)` | For HUD Breath bar. |
| `sprint_available(available: bool)` | For Player sprint gating; false when breath < sprint_gate. |

**Functions:**

| Function | Description |
|---|---|
| `set_sprinting(active: bool) -> void` | Toggles continuous sprint drain. |
| `spend(amount: float) -> bool` | Deducts a burst-action cost; returns false if `breath < amount` (action blocked). |
| `can_sprint() -> bool` | Returns `breath > sprint_gate`. |
| `reset() -> void` | Sets breath to max_breath (called on sleep). |

#### Class: StaminaComponent

**Extends:** Node
**Script:** `stamina_component.gd` (in `combat/`)
**Description:** Long-term daily energy pool. Self-ticking. Ambient drain (×2 while working). Sleep-only recovery. Causes collapse at 0%. Applies work/movement penalties via bands.
**Used by:** Player (movement floor + work multiplier), Colonists (work multiplier + collapse). HUD (Stamina bar + status icon). Colonist AI (collapse halt).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `stamina` | `float` | Current value, 0–100. |
| `max_stamina` | `float` | [export] 100. |
| `drain_rate` | `float` | [export] 0.21/min (ambient, per-character from CharacterDef). |
| `work_multiplier` | `float` | [export] 2.0 — drain is multiplied by this while `working` is true. |
| `working` | `bool` | Set true during active work Jobs. |
| `band` | `StaminaBand` enum | FRESH / TIRED / EXHAUSTED / COLLAPSED. Derived from stamina. |

**Signals:**

| Signal | Description |
|---|---|
| `stamina_changed(value: float)` | For HUD Stamina bar. |
| `stamina_band_changed(band: StaminaBand)` | For HUD status icon, Player movement floor, colonist AI collapse halt. |

**Functions:**

| Function | Description |
|---|---|
| `set_working(active: bool) -> void` | Toggles the `work_multiplier` on the drain. |
| `reset() -> void` | Sets stamina to max_stamina + band to FRESH (called on sleep). |
| `get_work_multiplier() -> float` | Returns the effective work-speed multiplier (1.0 fresh → 0.6 at collapse). |
| `get_move_multiplier() -> float` | Returns the effective movement-speed multiplier (1.0 fresh → 0.4 at collapse). |

---

## Subsystem: Permadeath & Memorial

> **Stub** — minimal architecture to give the `colonist_died` signal a real listener (resolves the "fires into the void" correctness bug). Deeper permadeath mechanics (named-vs-unnamed resolution, "left behind on retreat" rule, incapacitated-state handling) are TODO; tracked in `GDD.gaps.md`.

Tracks deceased colonists as a memorial roster, consumed by the Day Summary "Fallen" section and the Game Over screen. Lives on the **Colony autoload** (roster state must persist across base↔POI scene swaps).

### Files

| File | Type | Responsibility |
|---|---|---|
| `memorial.gd` | Script (on Colony autoload) | Appends to the roster on `colonist_died`; exposes `get_roster()` for UI. Does NOT own death detection (subscribes to the signal). Does NOT own the Game Over evaluator (TODO — see D3 in review notes). |
| `memorial_entry.tscn` | Scene | Reusable subscene: one deceased-colonist row (name, cause of death, day died). Instanced by Day Summary + Game Over. |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist_base.gd` (Combat) | **Memorial** (appends), Colony (roster removal), HUD | Yes | Colonist Death |

(Memorial itself emits no signals — UI polls `get_roster()` when it opens.)

### Flow Trace: Colonist death → memorial entry

**Trigger:** A colonist's HP hits 0 (Combat's damage resolution emits `entity_died` → `colonist_base.gd` emits `colonist_died` via EventBus).

1. `colonist_base.gd` emits `colonist_died(colonist_id)` via EventBus.
2. **Memorial** (on Colony) listens → appends `{colonist_id, display_name, cause, day_died}` to roster.
3. **Colony** (roster manager) listens → removes colonist from the active roster; re-evaluates Game Over condition (all colonists + player dead → emit `game_over` via EventBus).
4. **HUD** listens → shows death notification (status icon / brief toast).
5. Next Day Summary (on sleep) and any Game Over screen read `Memorial.get_roster()` to render the Fallen section.

**End state:** Colonist removed from active roster; memorial entry persists for the rest of the run; Game Over condition re-checked.

### Class Reference

#### Class: Memorial

**Extends:** Node (child of Colony autoload)
**Script:** `memorial.gd`
**Description:** Append-only roster of deceased colonists. Subscribes to `colonist_died`; queried by Day Summary + Game Over UI.
**Used by:** UI (Day Summary, Game Over).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `roster` | `Array[Dictionary]` | Each entry: `{colonist_id, display_name, cause, day_died}`. |

**Functions:**

| Function | Description |
|---|---|
| `get_roster() -> Array[Dictionary]` | Returns the memorial roster (for UI rendering). |
| `_on_colonist_died(colonist_id: String, cause: String) -> void` | EventBus listener; appends an entry using current GameState day. |

---

## Subsystem: Raids

Raid scheduler, threat-direction weights, spawn manager. GDD §17 Raids subsystem.

### Files

| File | Type | Responsibility |
|---|---|---|
| `raid_scheduler.gd` | Script (on WorldRoot, base scene only) | Triggers raids per escalation curve; emits `raid_started`. Does NOT own enemy spawning (SpawnManager does). |
| `threat_model.gd` | Script (on Colony autoload) | Per-edge threat weights; POI visit bump, decay, random floor. |
| `spawn_manager.gd` | Script | Spawns enemies at chosen edge; enforces 24-enemy cap; throttles waves. |
| `../data/raid_curve.tres` | Data | Escalation table (D1–D20+ waves/enemies/shooter %). |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `raid_started(raid_data)` | `raid_scheduler.gd` | HUD, Colony, colonists | Yes | Raid Begins |
| `raid_ended(outcome)` | `raid_scheduler.gd` | HUD, Colony, SaveSystem | Yes | Raid Resolves |

### Flow Trace: Nightly raid begins

**Trigger:** TimeSystem emits `day_rolled_over` (midnight).

1. RaidScheduler listens; checks colony size (≥ 3 colonists required — safety net).
2. Looks up wave count + enemies/wave for `current_day` in `raid_curve.tres`.
3. ThreatModel selects weighted-random edge; SpawnManager gets spawn points along edge.
4. RaidScheduler emits `raid_started` via EventBus.
5. Colony assigns colonists to their raid stances (Fight/Fight Post/Shelter).
6. SpawnManager spawns wave 1; respects 24-enemy cap.

**End state:** Raid in progress; colonists in stance; enemies spawning.

### Class Reference

#### Class: ThreatModel

**Extends:** Node
**Script:** `threat_model.gd`
**Description:** Per-edge threat weights (N/S/E/W). Owned by Colony autoload because POI visits (which bump weights) happen during expeditions. The visibility bonus (+3 per functional-furniture item to all edges) is applied here via `Colony.count_functional_furniture()` (see Functional Rooms subsystem — **planned, not yet built**).
**Used by:** Raids (edge selection), Expeditions (POI visit bumps weights).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `weights` | `Dictionary[String, int]` | Edge → weight (start 25 each). |

**Functions:**

| Function | Description |
|---|---|
| `bump_edge(edge: String, amount: int) -> void` | POI visit raises edge weight. |
| `apply_visibility_bonus() -> void` | Adds `Colony.count_functional_furniture() × 3` to all edges. Called at raid-start. *(Depends on Functional Rooms — planned.)* |
| `decay_all() -> void` | Daily −2/edge, floored at 10. |
| `select_edge() -> String` | Weighted-random + 10% floor. |

---

## Subsystem: Expeditions

Scavenge mission (Timed Extraction), world map, POI scene. GDD §17 Expeditions.

### Files

| File | Type | Responsibility |
|---|---|---|
| `world_map.tscn` / `world_map.gd` | Scene/Script | Hex-grid sector map; fog states; POI icons; travel cost display. Full-screen UI (CanvasLayer 20). |
| `poi_scene.tscn` | Scene | Generic POI scene; parameterized by POI data. Contains `LootContainer` instances (see Loot subsystem). Loaded by SceneManager on expedition start. |
| `scavenge_mission.gd` | Script | Phase timer (free-loot → waves), extraction at vehicle. Container counts per zone are placed here (4–6 total: 1 Zone A, 2 Zone B, 2 Zone C per GDD §17 map layout). |
| `../data/pois/` | Data | POI definitions (1 for MVP). |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `expedition_started(crew, poi_id)` | `scavenge_mission.gd` | SceneManager, Colony, colonists | Yes | Start Expedition |
| `expedition_ended(result)` | `scavenge_mission.gd` | SceneManager, Colony, HUD | Yes | End Expedition |

### Flow Trace: Scavenge mission (Timed Extraction)

**Trigger:** Player selects a POI on the world map + crew, confirms.

1. `world_map.gd` calls SceneManager to swap WorldRoot → `poi_scene.tscn`.
2. EventBus emits `expedition_started(crew, poi_id)`.
3. Colony marks crew as "on expedition" (removed from base scene).
4. ThreatModel bumps the POI's edge weight +15.
5. Scavenge mission: 0:30–3:00 free loot window; at 2:30 warning; waves from 3:00.
6. Player returns to vehicle → extract → `expedition_ended({success/partial/narrow})`.
7. SceneManager swaps back to base scene; crew restored.

**End state:** Back at base; loot banked; crew restored; edge weight raised.

---

## Subsystem: Loot

Loot tables + container-roll logic for scavenge missions. GDD §17 "Loot tables" + "Key Item Table". Consumed by Expeditions (containers in POI scenes); output flows to Inventory on pickup. Cross-references: Expeditions subsystem (containers live in POI scenes), Inventory subsystem (pickup flow), SaveSystem (Key Item pool persists).

**Design notes:**
- **LootTable + LootEntry** are data (`.tres` Resources); the **roller** is a script. Matches the data-driven convention.
- **KeyItemPool lives on the Colony autoload** — run-state that must persist across scene swaps and saves (Key Items are once-per-playthrough). Same pattern as Memorial. See Tech Debt on Colony bloat.
- Containers roll **on interaction** (not mission start), per GDD §17. A single container's contents are computed when the player loots it; the result then flows through the standard Inventory pickup.

### Files

| File | Type | Responsibility |
|---|---|---|
| `loot_container.gd` | Script | A lootable object in a POI scene. Holds a `LootTable` reference; on interact, rolls and offers results to the player's Inventory. Does NOT own the table data or the Key Item pool. |
| `loot_roller.gd` | Script (static) | Pure roll math: given a `LootTable`, returns a `Dictionary[item_id, count]`. No state, no signals. |
| `../autoloads/colony.gd` (`KeyItemPool`) | Subsystem on Colony | Tracks which Key Items have dropped this run; `roll_key_item()` returns one or null. Once-per-playthrough enforcement. |
| `../data/loot/standard.tres` | Data | Standard Container table (Zones A/B). See Data Schema. |
| `../data/loot/deep.tres` | Data | Deep Loot Container table (Zone C). See Data Schema. |
| `../data/loot/key_items.tres` | Data | Key Item pool (7 MVP items + their T2 upgrade targets). See Data Schema. |

### Signals

Loot is local to the POI scene + Inventory — no cross-scene signals. The Key Item pool emits nothing (Inventory queries it via `LootContainer` on a successful Key Item roll).

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| *(none — Loot uses direct refs and the Inventory pickup flow)* | — | — | — | Loot a Container |

### Flow Trace: Loot a container

**Trigger:** Player interacts (E) with a LootContainer in a POI scene.

1. `LootContainer.on_interact()` calls `LootRoller.roll(table)` with its assigned `LootTable` (standard or deep).
2. `LootRoller` iterates the table's entries: for each, roll the % chance; on success, pick a count in [min, max].
3. If a Key Item entry succeeds: `LootContainer` calls `Colony.key_item_pool.roll_key_item()` — returns a Key Item ID (and marks it as dropped) or null (all already found this run).
4. `LootContainer` aggregates results into a list of `{item_id, count}` and offers them to `Player.inventory.add(item_id, count)` via the standard Inventory pickup flow (stacking, partial-accept, remainder rules per Inventory subsystem).
5. On full accept: container marked looted (despawned / opened visual). On partial (inventory full): remainder stays in the world per Inventory rules; container stays interactable.

**End state:** Looted items in player inventory; container state updated; any Key Item marked as found for the run.

### Flow Trace: Key Item drop is once-per-playthrough

**Trigger:** A loot roll succeeds on a Key Item entry (5% standard / 20% deep).

1. `LootRoller` returns a "key_item_pending" result to `LootContainer`.
2. `LootContainer` calls `Colony.key_item_pool.roll_key_item()`.
3. `KeyItemPool` checks its `found: Array[String]` list:
   - If unfound items remain → picks one at random, adds its ID to `found`, returns the ID.
   - If all have been found → returns null (no drop this time).
4. `LootContainer` proceeds with the returned ID (or skips if null).
5. On save: `KeyItemPool.found` is serialized as part of Colony state (see SaveSystem tracked-state list).

**End state:** Each Key Item drops at most once per playthrough; progression gated by exploration, not luck.

### Class Reference

#### Class: LootContainer

**Extends:** Node3D (or Area3D for proximity prompt)
**Script:** `loot_container.gd` (in `loot/`)
**Description:** A lootable object placed in a POI scene. Holds a `LootTable` reference; rolls on interact; offers results to Inventory. Does NOT own table data or the Key Item pool.
**Used by:** Expeditions (containers placed in `poi_scene.tscn`), Inventory (pickup flow).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `loot_table` | `LootTable` | [export] The table to roll from (standard or deep). |
| `looted` | `bool` | True after a successful full loot; gates re-interaction. |

**Functions:**

| Function | Description |
|---|---|
| `on_interact(player: Node) -> void` | Rolls the table, resolves Key Item via Colony, offers results to `player.inventory`. |

#### Class: LootRoller

**Extends:** RefCounted (static class)
**Script:** `loot_roller.gd` (in `loot/`)
**Description:** Pure roll math. No state, no signals. Reads a `LootTable`, returns item/count results.
**Used by:** LootContainer.

**Functions:**

| Function | Description |
|---|---|
| `static roll(table: LootTable) -> Array[Dictionary]` | Returns `[{item_id, count}, ...]`. Per-entry % chance roll; count in [min, max]. Key Item entries return `{item_id: "key_item_pending"}` for the caller to resolve via KeyItemPool. |

#### Class: KeyItemPool

**Extends:** Node (child of Colony autoload)
**Script:** `key_item_pool.gd` (in `loot/`, or `autoloads/` if you prefer all Colony children there)
**Description:** Once-per-playthrough enforcement for Key Items. Tracks found items; `roll_key_item()` returns one or null. State is saved with Colony.
**Used by:** LootContainer (on a Key Item roll success).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `pool` | `KeyItemPoolDef` | Loaded from `data/loot/key_items.tres` — the full list of possible Key Items. |
| `found` | `Array[String]` | Key Item IDs already dropped this run. Saved with Colony state. |

**Functions:**

| Function | Description |
|---|---|
| `roll_key_item() -> String` | Returns a random unfound Key Item ID (and adds it to `found`), or empty string if all found. |

---

## Subsystem: Inventory

Items, stacks, inventory model. GDD §4.5, §7.3.

### Files

| File | Type | Responsibility |
|---|---|---|
| `inventory.gd` | Script (on Player node) | Player's inventory: 30 slots (10 hotbar + 20 general). Owns stacking algorithm. Does NOT own UI (Inventory screen reads this). |
| `item_stack.gd` | Script | A stack of one item type; count up to cap. |
| `storage_crate.gd` | Script | Shared colony storage node; proximity access (2m); 32-stack cap per crate. |
| `../data/items/` | Data | Item definitions (id, name, icon, stack cap, usable flag). |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `inventory_changed()` | `inventory.gd` | Inventory screen, HUD hotbar | No (same scene / direct ref) | Pickup Item |
| `item_picked_up(item_id, count)` | `inventory.gd` | HUD (refresh) | Yes (for HUD when Player screen closed) | Pickup Item |

### Flow Trace: Pickup item (no auto-pickup; interact or container)

**Trigger:** Player presses E on a world item, or takes from a container.

1. Player emits `interact_started(target)` → target's interact handler.
2. World item / crate offers `{item_id, count}` to `Player.inventory.add(item_id, count)`.
3. Inventory runs stacking algorithm:
   - Fill existing same-type stacks to cap.
   - Overflow → new non-hotbar slot (prefer non-hotbar).
   - If no slot: container subtracts transferred; world item re-drops remainder.
4. Inventory emits `inventory_changed()` (direct) + `item_picked_up` via EventBus.
5. Inventory screen / HUD hotbar refresh.

**End state:** Item in inventory (full or partial); source updated; UI refreshed.

### Class Reference

#### Class: Inventory

**Extends:** Node
**Script:** `inventory.gd`
**Description:** Player's inventory model. 30 slots; stacking per GDD §4.5. Owned by Player; UI reads/writes via public methods.
**Used by:** UI (Inventory screen, HUD hotbar), Combat (weapon/ammo consumption).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `slots` | `Array[ItemStack]` | 30 slots; first 10 = hotbar. |
| `slot_count` | `int` | [export] 30. |

**Functions:**

| Function | Description |
|---|---|
| `add(item_id: String, count: int) -> int` | Stacks per algorithm; returns overflow not stored. |
| `remove(item_id: String, count: int) -> int` | Returns actually removed. |
| `get_hotbar() -> Array[ItemStack]` | First 10 slots. |

---

## Subsystem: Crafting

Recipe-driven conversion of materials into furniture, armor, weapons, ammo, and refined materials. GDD §7.9. Consumes from Inventory/colony storage; produces items back into storage. Craft Jobs register on the Job Board (no special-casing — they're Jobs like any other).

**Design notes:**
- **One unified `Recipe` data structure** for all craftable output (furniture, armor, weapons, ammo, smelting). Same shape regardless of output type.
- **`CraftingStation` is a furniture component** (attached to Workbench/Forge nodes) — owns the "which recipes are available here?" check. The recipe data itself lives in `data/recipes/`.
- **No tech tree in MVP** — all recipes available from the start; the constraint is materials + station + L1 skill gate. Post-MVP: unlocking.
- **Material flow goes through colony storage** (StorageCrate proximity per Inventory subsystem), not the colonist's personal inventory. This is why Hauling exists as a Labor — craft Jobs depend on materials being hauled to accessible storage.

### Files

| File | Type | Responsibility |
|---|---|---|
| `recipe.gd` | Script (Resource) | Data shape for one recipe: output, inputs, station, skill, base_time. Pure data; no behavior. See Data Schema. |
| `crafting_station.gd` | Script (component on furniture) | Attached to Workbench/Forge nodes. Owns the recipe list available at this station; registers craft Jobs on the Job Board. Does NOT own the craft math (Job Board + Skills + Stamina handle that). |
| `../data/recipes/workbench.tres` | Data | RecipeList for the Workbench (furniture, armor, weapons, ammo). See Data Schema. |
| `../data/recipes/forge.tres` | Data | RecipeList for the Forge (smelting: ore→metal, scrap→components, metal+components→reinforced). See Data Schema. |

### Signals

Crafting is local to the base scene + Colony (Job Board). No cross-scene signals.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `craft_started(recipe_id, colonist_id)` | `crafting_station.gd` | HUD (optional notification) | No | Craft Job Executes |
| `craft_completed(recipe_id, output)` | `crafting_station.gd` | HUD (notification), Day Summary (production log) | No | Craft Job Executes |

### Flow Trace: Player queues a craft (Workbench)

**Trigger:** Player opens Workbench UI (or colony craft list), selects a recipe, confirms.

1. `CraftingStation` (on the Workbench node) receives the queue request with `recipe_id`.
2. Validates: recipe belongs to this station; player/colony has the materials in accessible storage (queries StorageCrate inventory via Inventory subsystem).
3. If materials available: reserves them (removed from storage now to prevent double-spend); creates a craft Job on the Job Board with `{recipe_id, station, base_time, skill: crafting}`.
4. If materials missing: reject the queue; emit nothing (UI shows "missing materials").

**End state:** Craft Job on the board; materials reserved; awaiting a colonist (or the player) to claim it.

### Flow Trace: Craft Job executes (colonist claims + completes)

**Trigger:** A colonist (or player) claims the craft Job via the standard Job Board flow (§6.10).

1. Colonist AI claims the Job; paths to the station (A* on voxel grid).
2. On arrival: `stamina_component.set_working(true)` (×2 drain active).
3. Each work tick: progress += `recipe.base_time × skill_set.get_multiplier("crafting") × stamina_component.get_work_multiplier() × delta`.
4. On progress ≥ `recipe.base_time`: craft completes.
5. `CraftingStation` consumes the reserved materials; produces `recipe.output_item × recipe.output_count` into colony storage (via Inventory add flow).
6. Emits `craft_completed(recipe_id, output)`; HUD notifies; Day Summary logs.
7. `skill_set.record_use("crafting")` grants skill progress; `stamina_component.set_working(false)`.
8. Job Board marks Job complete; colonist seeks next.

**End state:** Materials consumed; output in storage; Crafting skill progressed; Stamina burned at ×2; Job closed.

### Flow Trace: Smelting at the Forge (same flow, different station/skill)

**Trigger:** Player queues a smelting recipe (ore→metal, scrap→components, etc.) at the Forge.

1. Identical to the Workbench flow above, with substitutions:
   - Station = Forge (`crafting_station.gd` with `forge.tres` recipe list).
   - Skill = Smelting (not Crafting).
2. Same material-reservation, Job-Board, work-tick, skill-progress, output-deposit steps.

**End state:** Ore/scrap consumed; refined material in storage; Smelting skill progressed.

### Class Reference

#### Class: CraftingStation

**Extends:** Node (component on furniture nodes — Workbench, Forge)
**Script:** `crafting_station.gd` (in `crafting/`)
**Description:** Attached to crafting-furniture nodes. Holds the station's recipe list; validates material availability; registers/reserves craft Jobs on the Job Board; produces output on completion. Does NOT own craft math (Skills + Stamina + Job Board handle the tick).
**Used by:** UI (craft list / queue), Colonists (Job Board claim → path → station).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `station_id` | `String` | `"workbench"` or `"forge"`. |
| `recipes` | `RecipeList` | Loaded from `data/recipes/<station>.tres`. |
| `active_jobs` | `Array[String]` | Job IDs currently reserved at this station (for UI + cap if needed). |

**Signals:**

| Signal | Description |
|---|---|
| `craft_started(recipe_id: String, colonist_id: String)` | Optional HUD notification. |
| `craft_completed(recipe_id: String, output: Dictionary)` | `{item_id, count}` produced; HUD + Day Summary log. |

**Functions:**

| Function | Description |
|---|---|
| `queue_craft(recipe_id: String) -> bool` | Validates materials + station; reserves materials; creates Job on Job Board. Returns false if invalid. |
| `get_available_recipes() -> Array[Recipe]` | All recipes this station can craft (filtered by station_id; no tech-tree gating in MVP). |

---

## Subsystem: UI

HUD + all full-screen UIs. Each screen is its own `.tscn` scene; reusable subscenes (health bar, inventory slot, roster row) are standalone scenes.

### Files

| File | Type | Responsibility |
|---|---|---|
| `hud/hud.tscn` / `hud.gd` | Scene/Script | Persistent in-game overlay (CanvasLayer 10): HP/Durability/Stamina/Breath bars, hotbar, build overlay, day counter. |
| `player_screen/player_screen.tscn` | Scene | Tabbed: Player Info / Inventory / Gear / Skills(empty). |
| `colony_screen/colony_screen.tscn` | Scene | Tabs: Roster / Labor / Defense / Loadouts / Expeditions. |
| `world_map/world_map.tscn` | Scene | Hex-grid map (also referenced by Expeditions subsystem). |
| `pause_menu/pause_menu.tscn` | Scene | Resume / Settings / Quit. |
| `main_menu/main_menu.tscn` | Scene | New / Continue / Load / Settings / Quit. |
| `game_over/game_over.tscn` | Scene | Stats + memorial roster (reads from Memorial) + buttons. |
| `day_summary/day_summary.tscn` | Scene | Post-sleep screen (CanvasLayer 20): day's resource changes, expeditions, Fallen section (reads Memorial), construction, raids survived. See Core "Sleep → Day Summary → Save" flow. |
| `settings/settings.tscn` | Scene | Video / Audio tabs. |
| `shared/health_bar.tscn` | Scene | Reusable subscene: HP + Durability bars. |
| `shared/inventory_slot.tscn` | Scene | Reusable subscene: one inventory slot. |
| `shared/roster_row.tscn` | Scene | Reusable subscene: one colonist row in Roster tab. |
| `shared/job_log_entry.tscn` | Scene | Reusable subscene: one Job Log line. |
| `shared/memorial_entry.tscn` | Scene | Reusable subscene: one deceased-colonist row (name, cause, day died). Instanced by Day Summary + Game Over. |

### Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `screen_opened(screen_id)` | each screen's `.gd` | GameState (pause), HUD (hide) | No (SceneManager-mediated) | Open Full-Screen UI |
| `screen_closed(screen_id)` | each screen's `.gd` | GameState (unpause), HUD (show) | No | Close Full-Screen UI |

### Flow Trace: Open Player screen (Z key)

**Trigger:** Player presses Z.

1. Player input → SceneManager.open_screen("player_screen").
2. SceneManager instances `player_screen.tscn` in CanvasLayer 20.
3. Player screen emits `screen_opened` → GameState pauses sim, HUD hides.
4. Player screen reads from Player.inventory, Player.gear, Player.stats.
5. Player presses Esc → `screen_closed` → inverse.

**End state:** Player screen open; game paused; HUD hidden.

---

## Subsystem: Debug Console

Dev/playtest console for rapid iteration. GDD §17 Debug Console + the scavenge-specific hooks in §17 Expeditions. **Dev-only — stripped from release builds** (see Tech Debt on the export-time exclusion approach).

**Design notes:**
- **Command registry pattern:** a `DebugConsole` autoload (or scene on a CanvasLayer) holds a registry of `command_name → callable`. Each command is a thin function that mutates state via the *public APIs* of other subsystems (Inventory.add, Colony.spawn_colonist, etc.) — never reaches into subsystem internals. This keeps the debug surface from rotting when subsystem internals change.
- **`id` convention:** commands that take an entity id accept either a colonist_id or the literal string `"player"`. A small resolver (`DebugConsole._resolve_entity(id)`) returns the node; commands query the relevant component on it.
- **Command discovery:** `help` lists all registered commands; tab-completion against the registry. (Both are console-UX details, not GDD-specced, but trivial to include.)
- **Scavenge-specific commands** (force_loot_window, fill_containers, etc.) only function during an active scavenge mission; the registry still holds them, they just early-return with an error if the mission context isn't active.

### Files

| File | Type | Responsibility |
|---|---|---|
| `debug_console.tscn` / `debug_console.gd` | Scene/Script | The console UI (CanvasLayer, toggled by `~` or F1). Owns the command registry; parses input lines; dispatches to registered callables. Renders output history. Does NOT contain command logic itself (commands are registered from their owning subsystems or a central `commands.gd`). |
| `commands.gd` | Script | Central registration of all debug commands as thin wrappers over subsystem public APIs. Loaded by `debug_console.gd` on ready. Each function is one command. |
| `command.gd` | Script (Resource) | Data shape for one registry entry: name, arg spec, help text, callable. |

### Signals

Debug is dev-only and reads/writes state directly via callables — no signals needed. (Console output is written to the console's own buffer, not broadcast.)

### Flow Trace: Player runs a debug command

**Trigger:** Developer/playtester types a command in the console (e.g. `add_resource leather 50`).

1. `debug_console.gd` parses the input line into `[command_name, *args]`.
2. Looks up `command_name` in the registry → gets the `Command` resource (callable + arg spec).
3. Validates arg count/types against the spec; on mismatch, prints usage to console output.
4. Calls the callable with the args. The callable (in `commands.gd`) mutates state via the relevant subsystem's public API:
   - `add_resource` → `Player.inventory.add(item_id, count)` (or colony storage; TBD per Inventory subsystem's "where do added resources go" — flag for Inventory review).
   - `set_hp` → `DebugConsole._resolve_entity(id).health_component.hp = value`.
   - `spawn_wave` → `SpawnManager.spawn_wave(n, edge)`.
   - etc.
5. Callable returns a result string → console prints it to output history.

**End state:** Game state mutated per the command; output shown in console; simulation continues.

### Class Reference

#### Class: DebugConsole

**Extends:** CanvasLayer (or Control on a CanvasLayer)
**Script:** `debug_console.gd` (in `debug/`)
**Description:** The console UI + command dispatcher. Holds the command registry; parses input; routes to callables. Dev-only.
**Used by:** (dev only — not referenced by gameplay code).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `registry` | `Dictionary[String, Command]` | command_name → Command resource. |
| `visible` | `bool` | Toggled by `~` / F1. |

**Functions:**

| Function | Description |
|---|---|
| `register_command(cmd: Command) -> void` | Called by `commands.gd` on ready for each command. |
| `execute(input: String) -> void` | Parses + dispatches a console input line. |
| `_resolve_entity(id: String) -> Node` | Returns the player node for `"player"`, else the colonist by id. Used by stat-setter commands. |

### Command Reference

Full list of registered commands. GDD §17 Debug Console + §17 Scavenge-specific hooks. All dev/playtest only.

**Resources:**

| Command | Effect |
|---|---|
| `add_resource [item_id] [n]` | Adds n of any item (first arg is the `item_def_id`: scrap, wood, leather, med_supplies, etc.). |

**Characters (player + colonists via id; `"player"` for the player):**

| Command | Effect |
|---|---|
| `spawn_survivor` | Spawns a generic unnamed colonist at base. |
| `kill_survivor [id]` | Triggers permadeath on a colonist. |
| `set_hp [id] [value]` | Sets HP on any character. |
| `set_durability [id] [value]` | Sets Durability on any character. |
| `set_stamina [id] [value]` | Sets Stamina (0–100%) on any character. |
| `set_breath [id] [value]` | Sets Breath (0–100%) on any character. |

**Expeditions / travel:**

| Command | Effect |
|---|---|
| `teleport_mission` | Teleports player to currently selected expedition map. |
| `teleport_extraction` | Teleports player to vehicle extraction point (scavenge-only). |
| `set_loot_window [seconds]` | Overrides free loot window duration (scavenge-only). |
| `fill_containers` | Sets all containers to max loot values (scavenge-only). |
| `force_key_item [name]` | Forces a specific Key Item into the next container (scavenge-only). |
| `skip_to_wave [n]` | Fast-forwards wave timer to wave n (scavenge-only). |
| `mission_summary_preview` | Mock Day Summary with test values (scavenge-only). |

**Raids / threat:**

| Command | Effect |
|---|---|
| `spawn_wave [n] [edge?]` | Spawns wave n at edge (omit for weighted-random). Also used scavenge-only with no edge (north). |
| `set_threat [edge] [value]` | Sets threat weight 0–100 for an edge. |
| `show_threat_weights` | Displays threat weights in debug overlay. |

**World map / fog:**

| Command | Effect |
|---|---|
| `reveal_sector [id]` | Forces sector to Visited, reveals neighbors. |
| `fog_all` | Resets all sectors to Fogged (except home neighbors). |

**Time / progression:**

| Command | Effect |
|---|---|
| `fast_time` | Toggles accelerated time passage. |
| `win_game` | Triggers victory state (post-MVP feature; command tests the flow). |

**Build:**

| Command | Effect |
|---|---|
| `place_block [type] [x] [y] [z]` | Places a voxel block instantly (bypasses construction). |

**Cheats:**

| Command | Effect |
|---|---|
| `god_mode` | Player and colonists take no damage. |

---

## Data Schemas

### `data/game_config.tres` (Resource: `game_config.gd`)

| Field | Type | Description |
|---|---|---|
| `gravity` | `float` | 9.8 (Y). |
| `target_fps` | `int` | 60 (floor 30). |
| `loop_length_minutes` | `float` | 30 (1 in-game day). |
| `max_enemies_on_screen` | `int` | 24. |

### `data/characters/<type>.tres` (Resource: `character_def.gd`)

One CharacterDef per character type: `player.tres`, `colonist.tres`, `companion.tres`, `brawler.tres`, `shooter.tres`. Union schema — all fields exist; unused ones default to 0/null. Supersedes the retired `data/player_stats.tres` and `data/enemies/`.

| Field | Type | Applies to | Description |
|---|---|---|---|
| `display_name` | `String` | All | UI label. |
| `character_type` | `CharacterType` enum | All | PLAYER / COLONIST / COMPANION / ENEMY. |
| `max_hp` | `int` | All | 200 (player) / 100 (colonist) / 120 (companion) / 140,60 (enemies). |
| `max_durability` | `int` | All | 0 for enemies (no armor in MVP); sum of equipped armor otherwise. |
| `base_move_speed` | `float` | All | Player 3.5; Brawler 2.1; Shooter 2.98. |
| `sprint_multiplier` | `float` | Player | 1.6×. Unused by others (no sprint in MVP). |
| `stamina_drain_rate` | `float` | Player, Colonist, Companion | −0.21/min ambient. Unused by enemies (no StaminaComponent). |
| `breath_sprint_drain` | `float` | All | 20/sec. |
| `breath_jump_cost` | `float` | All | 10. |
| `breath_melee_cost` | `float` | All | 5. |
| `breath_ranged_cost` | `float` | All | 2. |
| `breath_regen_rate` | `float` | All | 10/sec. |
| `detection_range` | `float` | Enemies | Brawler 10m; Shooter 16m. Unused by player/colonist. |
| `damage` | `int` | Enemies | Brawler 25 melee; Shooter 12 ranged. Unused by player (player damage comes from weapons). |
| `attack_range` | `float` | Enemies | Brawler 1.5m; Shooter 10m (holding). Unused by player. |

### `data/energy_config.tres` (Resource: `energy_config.gd`)

Global Energy values (shared across all characters). Per-character rates (Stamina drain, Breath costs) live in `data/characters/`.

| Field | Type | Description |
|---|---|---|
| `work_threshold` | `float` | 0.45 — Stamina below this triggers Tired band (work penalty). |
| `move_threshold` | `float` | 0.25 — Stamina below this triggers Exhausted band (move penalty too). |
| `collapse_threshold` | `float` | 0.0 — Stamina at this triggers Collapsed band. |
| `work_floor` | `float` | 0.6 — minimum work-speed multiplier (at collapse). |
| `move_floor` | `float` | 0.4 — minimum move-speed multiplier (at collapse). |
| `stamina_work_multiplier` | `float` | 2.0 — drain multiplier while `working == true`. |
| `sprint_gate` | `float` | 0.20 — Breath below this blocks sprint. |

### `data/blocks/<type>.tres` (Resource: `block_def.gd`)

| Field | Type | Description |
|---|---|---|
| `block_id` | `String` | e.g. `"wood"`, `"scrap"`, `"stone"`. |
| `hp` | `int` | Block HP (50/100/300/600/1200). |
| `mesh` | `Mesh` | Blocky-mode mesh (unit cube). |
| `material_cost` | `Dictionary` | Resource → count (e.g. `{wood: 3}`). |

### `data/raid_curve.tres` (Resource: `raid_curve.gd`)

Array of `{day_threshold, waves, enemies_per_wave, shooter_percent}` rows. See GDD §17 Raids for values.

### `data/items/<id>.tres` (Resource: `item_def.gd`)

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | Unique. |
| `display_name` | `String` | UI label. |
| `icon` | `Texture2D` | Inventory icon. |
| `stack_cap` | `int` | Max per stack. |
| `usable` | `bool` | True if usable (healing, etc.). |

### `data/loot/<table>.tres` (Resource: `loot_table.gd`)

One per container type: `standard.tres` (Zones A/B), `deep.tres` (Zone C). Each table is an array of `LootEntry` resources (see `loot_entry.gd`). See GDD §17 "Loot tables" for the MVP values.

| Field | Type | Description |
|---|---|---|
| `table_id` | `String` | `"standard"` or `"deep"`. |
| `entries` | `Array[LootEntry]` | One per rollable item. See below. |

**LootEntry** (`loot_entry.gd extends Resource`) — one row of a loot table:

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | What this entry rolls (e.g. `"scrap"`, `"components"`, `"key_item_pending"`). |
| `min_count` | `int` | Minimum stack if the roll succeeds. |
| `max_count` | `int` | Maximum stack if the roll succeeds. |
| `drop_chance` | `float` | 0.0–1.0 probability per container roll. `1.0` = "always included". |

**Standard container values** (GDD §17): scrap 20–50 (1.0), components 5–15 (0.7), fuel 5–15 (0.4), med_supplies 1–3 (0.25), key_item_pending — — (0.05).
**Deep container values**: scrap 40–90 (1.0), components 10–25 (0.85), fuel 10–20 (0.55), med_supplies 2–5 (0.40), key_item_pending — — (0.20).

### `data/loot/key_items.tres` (Resource: `key_item_pool_def.gd`)

The Key Item pool. Each Key Item drops at most once per playthrough (enforced by `KeyItemPool.found` on the Colony autoload). See GDD §17 "Key Item Table".

| Field | Type | Description |
|---|---|---|
| `items` | `Array[KeyItemDef]` | The 7 MVP Key Items. See below. |

**KeyItemDef** (`key_item_def.gd extends Resource`):

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | e.g. `"radio_transceiver_unit"`. |
| `display_name` | `String` | UI label. |
| `upgrade_target` | `String` | The T2 base upgrade this item gates (e.g. `"command_center_t2"`). |

**MVP Key Items** (GDD §17): Radio Transceiver Unit (Command Center T2), Portable Generator (Workshop T2), Water Pump Motor (Farm T2), Medical Fridge Unit (Infirmary T2), Heavy Jack Lift (Garage T2), Insulation Panels (Living Quarters T2), Welding Gas Cylinders (Defenses T2).

### `data/skills/skills.tres` (Resource: `skill_def_list.gd`)

Global skill definitions: the 6 MVP skills, their Labor mappings, use-curves, and per-level work-speed multipliers. Loaded once and shared by all `SkillSet` components. See GDD §6.3.

| Field | Type | Description |
|---|---|---|
| `skills` | `Array[SkillDef]` | The 6 skills. See below. |

**SkillDef** (`skill_def.gd extends Resource`) — one skill:

| Field | Type | Description |
|---|---|---|
| `skill_id` | `String` | `"medical"`, `"mechanical"`, `"construction"`, `"crafting"`, `"combat"`, `"farming"`. |
| `display_name` | `String` | UI label. |
| `labor` | `String` | The Labor this skill governs (e.g. `"construction"`). Skills map 1:1 to Labors except Farming (no Labor in MVP). |
| `multipliers` | `Array[float]` | Work-speed multiplier per level, index 0–4 = L1–L5. Default `[1.0, 1.2, 1.4, 1.7, 2.0]`. |
| `use_curve` | `Array[int]` | Successful uses required to reach each level, index 0–3 = L2–L5. Default `[20, 50, 100, 200]`. |

**MVP skills** (GDD §6.3): Medical (Clinic Bed), Mechanical (Vehicle Lift), Construction (build/repair blocks), Crafting (Workbench + Forge), Combat (raids/expeditions), Farming (Growing Trough, post-MVP — progression tracked but no Labor to consume it yet).

### `data/recipes/<station>.tres` (Resource: `recipe_list.gd`)

One RecipeList per station: `workbench.tres` (furniture, armor, weapons, ammo), `forge.tres` (smelting). Each list is an array of `Recipe` resources. See GDD §7.9 + §17 Equipment for the MVP recipe values.

| Field | Type | Description |
|---|---|---|
| `station_id` | `String` | `"workbench"` or `"forge"`. |
| `recipes` | `Array[Recipe]` | All recipes craftable at this station. See below. |

**Recipe** (`recipe.gd extends Resource`) — one craftable output:

| Field | Type | Description |
|---|---|---|
| `recipe_id` | `String` | Unique; e.g. `"clinic_bed"`, `"leather_armor_body"`, `"knife"`, `"bullet"`, `"smelt_metal"`. |
| `output_item` | `String` | Item ID produced (e.g. `"clinic_bed"`, `"leather_armor_body"`). |
| `output_count` | `int` | How many of `output_item` per craft (usually 1; ammo may batch). |
| `inputs` | `Dictionary` | `{item_id: count}` consumed (e.g. `{scrap: 100}` for Clinic Bed; `{metal: 2}` for Knife). |
| `station_id` | `String` | Which station crafts this (must match the list's `station_id`). |
| `skill_id` | `String` | Governing skill: `"crafting"` for Workbench recipes, `"smelting"` (mapped via Crafting Labor) for Forge recipes. |
| `base_time` | `float` | Base craft time in seconds (modified by skill × Stamina multipliers at runtime). |

**MVP recipe sources** (values already in GDD, modeled here as Recipes):
- **Furniture** (GDD §7.2 Buildables `Materials` column): Clinic Bed `{scrap: 100}`, Workbench `{scrap: 60, components: 10}`, Forge `{scrap: 80, components: 20}`, Colonist Bed `{scrap: 40, components: 5}`, Command Desk `{scrap: 120, components: 30}`, Vehicle Lift `{scrap: 120, components: 40}`.
- **Armor** (GDD §17 Equipment, per-slot per-tier): e.g. Leather Body `{leather: 6}`, Cloth Body `{cloth: 4}`, Scrap Body `{scrap: 6}`.
- **Weapons + ammo** (GDD §17 Equipment): Knife `{metal: 2}`, Pistol `{metal: 5, components: 5}`, Bullet `{scrap: 1}`. (Club/Bow/arrows are post-MVP.)
- **Smelting** (GDD §7.3 items): Ore→Metal, Scrap→Components, Metal+Components→Reinforced.

### `data/loadouts/<template>.tres` (Resource: `loadout_template.gd`)

Player-created loadout templates, saved per run. Each template is an abstract slot→item_def_id mapping (resolved to concrete items from storage at equip time). Created/edited via the Colony screen Loadouts tab. See GDD §17 Equipment + §12.

| Field | Type | Description |
|---|---|---|
| `template_id` | `String` | Unique per run. |
| `display_name` | `String` | Player-assigned name. |
| `slots` | `Dictionary[String, String]` | slot_id → item_def_id. Keys: `"armor_head"`, `"armor_body"`, `"armor_arms"`, `"armor_legs"`, `"armor_feet"`, `"armor_hands"`, `"melee"`, `"ranged"`. Values are item_def_ids (e.g. `"leather_armor_body"`, `"knife"`). Missing/empty slots = unequipped. |

**Slot validity** (which item_def_ids can go in which slot):
- `armor_*` slots: armor defs matching the slot (e.g. `armor_body` accepts `cloth_armor_body`, `leather_armor_body`, `scrap_armor_body`).
- `melee`: weapon defs with `class == "melee"` (Knife in MVP; Club post-MVP).
- `ranged`: weapon defs with `class == "ranged"` (Pistol in MVP; Bow post-MVP).

**Equip resolution at runtime:** when auto-equip fires, LoadoutManager resolves each slot's `item_def_id` to the nearest unclaimed concrete item of that type in colony storage. If none available, the slot stays empty (partial equip; logged).

**MVP note:** templates are per-colonist (one template assigned per colonist). "Colonist Groups" (assign a template to a group of colonists) is pinned post-MVP per GDD §12.
