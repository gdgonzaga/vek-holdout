# Subsystem: AI & Behavior Trees

The **AI Subsystem** (`subsystems/ai/`) provides autonomous goal arbitration, dynamic needs management, and behavior tree execution for colonists and hostile agents. It integrates the [LimboAI](https://github.com/limboai/limboai) GDExtension module into Godot 4, replacing procedural state machines with data-driven behavior trees and Utility AI evaluation.

---

## Architecture Overview

The subsystem operates through a layered decision and execution hierarchy:

```
                  +-------------------------+
                  |     ColonistNeeds       |  (Decay rates, need levels: hunger, rest, rec)
                  +------------+------------+
                               |
                               v
                  +-------------------------+
                  |      ColonistBrain      |  (Utility arbitration every 1.5s, score curves)
                  +------------+------------+
                               | Writes current_goal & target_smart_object
                               v
                  +-------------------------+
                  |     LimboAI Blackboard  |  (Agent runtime state dictionary)
                  +------------+------------+
                               | Evaluated by
                               v
                  +-------------------------+
                  |        BTPlayer         |  (Ticks root BehaviorTree, e.g. colonist_root.tres)
                  +------------+------------+
                               | Drives custom BTTask leaves
                               v
+-------------------------------------------------------------------------------+
| BTActionClaimJob | BTActionNavigateTo | BTActionPerformWork | BTActionHaulBatch ... |
+-------------------------------------------------------------------------------+
```

---

## Core Components

### 1. `ColonistNeeds` (`subsystems/ai/colonist_needs.gd`)

Manages individual colonist need levels (hunger, rest, recreation) on a normalized `0.0` (fully depleted) to `1.0` (fully satisfied) scale.

- **Data-Driven Definitions**: Need properties are defined by `NeedDef` resources (`data/needs/*.tres`).
- **Decay Loop**: Evaluates `decay_per_second` during `_process(delta)` to decay active need values.
- **Persistence**: Implements `serialize() -> Dictionary` and `deserialize(data: Dictionary)` for SaveSystem compatibility.

### 2. `ColonistBrain` (`subsystems/ai/colonist_brain.gd`)

Utility AI goal arbitrator attached to colonists (`ColonistBrain` node).

- **Evaluation Interval**: Polls every 1.5 seconds (`EVAL_INTERVAL = 1.5`).
- **Score Calculation**: Evaluates needs via response curves (`NeedDef.response_curve`), scaled by spatial proximity penalties for available smart object targets (`def.target_group`).
- **Action Commitment Inertia**: Applies a `+0.30` score bonus to the currently active goal if no critical need threshold (`emergency_threshold <= 0.10`) is crossed, preventing goal flickering (thrashing).
- **Blackboard Output**: Writes winning goal (`&"work"`, `&"eat"`, `&"rest"`, `&"recreation"`) and target node/group into the agent's `Blackboard`.

### 3. `BTTreeFactory` (`subsystems/ai/bt_tree_factory.gd`)

Programmatic generator for core behavior tree resources. Provides factory methods for:
- `create_generic_work_tree()` -> `bt_generic_work.tres`
- `create_haul_tree()` -> `bt_haul_single_trip.tres`
- `create_colonist_root_tree()` -> `colonist_root.tres`
- `create_enemy_swarmer_tree()` -> `enemy_swarmer.tres`

---

## AIUtils

`subsystems/ai/ai_utils.gd` is a static-only helper class (`class_name AIUtils`) shared by ColonistBrain and the BT tasks below to avoid re-implementing the same scans/lookups per task: `find_nearest_in_group()` (nearest valid Node3D in a scene group), `resolve_job_def()` (unwraps a legacy `Job`, fractional `JobInstance`, or `WorkerClaim` to its `JobDef`), `extract_tool_requirements()` / `resolve_character_inventory()` / `is_edible_item()` / `drop_unneeded_items()`, and `resolve_anim_controller()`.

---

## Custom LimboAI Tasks

Custom tasks extend `BTAction` or `BTCondition` and reside in `subsystems/ai/tasks/`.

### Action Tasks (`subsystems/ai/tasks/actions/`)

| Task Class | Script | Description |
|---|---|---|
| `BTActionClaimJob` | `bt_action_claim_job.gd` | Queries `JobBoard.get_best_job_for()`, claims via `try_claim_units()` (fractional) or `try_assign()` (legacy `Job`), sets blackboard variables (`active_job`, `target_pos`, `source_node`, `target_node`), manages lazy tool acquisition, and triggers `EquipmentAudit.run_audit()` to reconcile desired gear. Legacy claims consult `JobDef.work_site` for the cycle's walk target (hauling: crate vs. sink by carry state). Spent claims and completed/cancelled jobs on the blackboard are dropped so a fresh claim is made instead of re-satisfying finished work. |
| `BTActionEquipTool` | `bt_action_equip_tool.gd` | Swaps the required tool from holster into main hand, or equips from carry inventory into main hand prior to work execution. |
| `BTActionNavigateTo` | `bt_action_navigate_to.gd` | Navigates the agent to `target_var` (Vector3 or Node3D) using VoxelPathfinder, checking arrival distance and applying blacklists on stuck/unreachable paths. The task's own variable is authoritative when it exists (a null value means "no target" and never falls through to the generic fallback vars), and only the task instance that last set the agent's path (the `bt_nav_path_owner` agent meta, shared with `BTActionWander`) may clear it on exit — sibling branches under the root `BTDynamicSelector` re-tick every frame and must not wipe each other's path. |
| `BTActionPerformWork` | `bt_action_perform_work.gd` | Executes one work cycle: plays `work_animation`, runs for the def-derived duration (`work_duration`, or dynamic `JobDef.begin` when that is 0.0, divided by the actor's skill multiplier), then fires the terminal effect — `apply_work_units()` on `JobInstance`/`WorkerClaim`, or `JobDef.complete(actor, job)` on legacy `Job`s (the def contract in ARCH Jobs). Releases `active_job`/`active_claim` (and the legacy assignee slot) once the cycle finishes so the next tick claims fresh work; a preempted cycle fires `JobDef.on_abort` to persist partial progress / release claims. |
| `BTActionHaulBatch` | `bt_action_haul_batch.gd` | Executes item pickup (mode 0) and deposit (mode 1) between inventory and storage targets. |
| `BTActionUseSmartObject` | `bt_action_use_smart_object.gd` | Interacts with smart objects (beds, dining tables, chairs) to satisfy colonist needs and play interaction animations. |
| `BTActionWander` | `bt_action_wander.gd` | Picks a random walkable point within a specified radius for idle movement. |
| `BTActionScanThreats` | `bt_action_scan_threats.gd` | Scans surrounding area for hostile targets. Generic over `threat_groups` — reused unmodified by both `enemy_swarmer.tres` (scanning `player`/`players`/`colonists`) and `colonist_root.tres` (scanning `enemies`). |
| `BTActionMeleeAttack` | `bt_action_melee_attack.gd` | Executes melee attack against target within range, dealing flat authored damage (enemy AI only — see `BTActionColonistCombatAttack` for weapon-resource-driven colonist attacks). |
| `BTActionBreachVoxel` | `bt_action_breach_voxel.gd` | Applies real per-material voxel HP damage (`BlockyGrid.apply_damage()`, resolved via `SceneManager.get_current_map().get_blocky_grid()`) to blocking voxel terrain obstructing enemy pathfinding. |
| `BTActionColonistCombatAttack` | `bt_action_colonist_combat_attack.gd` | Reactive colonist combat (GDD §6.7 "Fight" stance, MVP subset): fires/swings the colonist's equipped weapon via `ColonistCombat` at a `threat_target` already found by `BTActionScanThreats`. Halts any in-progress path (`set_path([])`) before attacking — never pursues. |

### Condition Tasks (`subsystems/ai/tasks/conditions/`)

| Task Class | Script | Description |
|---|---|---|
| `BTConditionHasTool` | `bt_condition_has_tool.gd` | Returns `SUCCESS` if the colonist has the required tool equipped for `active_job`. |
| `BTConditionInGroup` | `bt_condition_in_group.gd` | Returns `SUCCESS` if the target node belongs to a specified group. |
| `BTConditionPathBlocked` | `bt_condition_path_blocked.gd` | Returns `SUCCESS` if pathfinding returned an impassable or blocked path. |

---

## Blackboard Conventions

Agents communicate state between `ColonistBrain`, `BTPlayer`, and `BTTask` leaves using standardized Blackboard variable keys:

| Blackboard Key | Type | Description |
|---|---|---|
| `current_goal` | `StringName` | Active high-level goal (`&"work"`, `&"eat"`, `&"rest"`, `&"recreation"`, `&"none"`). |
| `target_smart_object` | `Node3D` / `StringName` | Target node or target group for need satisfaction. |
| `active_job` | `JobInstance` | Currently claimed job instance. |
| `target_pos` | `Vector3` | Target destination for navigation or work execution. |
| `source_node` | `Node3D` / `Vector3` | Pickup source location for hauling jobs. |
| `target_node` | `Node3D` / `Vector3` | Deposit/work target node for hauling or construction jobs. |
| `threat_target` | `Node3D` | Active combat target, written by `BTActionScanThreats` for both enemy and colonist behavior trees. |

---

## Behavior Trees (`data/ai/trees/`)

- **`colonist_root.tres`**: Master colonist behavior tree utilizing a `BTDynamicSelector` to prioritize reactive combat (any armed colonist fighting back, GDD §6.7) above emergency need satisfaction, which in turn takes priority over work execution and idle wandering.
- **`bt_generic_work.tres`**: Sequence executing job claim, tool validation, navigation, and work progress.
- **`bt_haul_single_trip.tres`**: Sequence executing haul job claim, source navigation, item loading, target navigation, and item unloading.
- **`enemy_swarmer.tres`**: Hostile swarmer behavior tree executing voxel breaching on blocked paths, melee attacks, threat chasing, and aggro scanning.

---

## Save & Load Persistence

- `ColonistNeeds` serializes its dictionary of need values (`hunger`, `rest`, `recreation`) via `serialize()`/`deserialize()`.
- `ColonistBrain` itself holds no persisted state: it has no `serialize`/`deserialize`. On `Colonist.deserialize`, the blackboard's `current_goal`/targets are not restored — `bt_player.restart()` resets the tree and `brain.evaluate_goals()` re-arbitrates fresh against the just-loaded needs/inventory.
- `JobBoard.serialize()`/`deserialize()` only round-trips `JobSequence` state; per-colonist job blacklists (`blacklist_job_for`) are in-memory only and do not survive a save/load.

---

## Detailed Guides & Gotchas

For a deep dive into the Utility AI decision pipeline, the 60 Hz LimboAI dynamic selector execution flow, and hard-learned edge cases (such as job capacity gates, self-occupancy, and state desync), see [AI Brain & Decision Making](ai-brain.md).
