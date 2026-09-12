# Subsystem: Colonists

The **Colonists** subsystem (`subsystems/colonists/`) manages colonist entity instances (`Colonist`), roster management via the `Colony` autoload singleton, utility goal selection (`ColonistBrain`), behavior tree execution (`BTPlayer`), dynamic needs (`ColonistNeeds`), and spatial voxel pathfinding (`VoxelPathfinder`).

---

## Component Architecture

```
                                  +-------------------+
                                  |     Colonist      |  (Entity root node)
                                  +---------+---------+
                                            |
        +-------------------+---------------+---------------+-------------------+
        |                   |                               |                   |
        v                   v                               v                   v
+---------------+   +---------------+               +---------------+   +---------------+
| ColonistBrain |   | ColonistNeeds |               |   BTPlayer    |   |VoxelPathfinder|
+---------------+   +---------------+               +---------------+   +-------+-------+
(Utility AI)        (Hunger/Rest/Rec)               (LimboAI Engine)            | delegates
                                                                                v
                                                                        +---------------+
                                                                        |Pathfinding-   |
                                                                        |Strategy       |
                                                                        +---------------+
                                                                        (4-Way, 8-Way,
                                                                         Smoothed, Theta*)

(Scene also mounts: ColonistAnimationController + AnimationPlayer [mixamo library] —
see the class reference below and docs/HOWTO-use-makehuman-mixamo.md. Also code-created in _ready:
CharacterInventory, HungerComponent, Equipment, and EquipmentVisualizer — see
docs/architecture/hunger.md and docs/architecture/equipment.md. Carry-inventory hygiene and
equipment fulfillment are BT-task-driven, not a dedicated component — see below.)
```

---

## Core Classes

### Class: Colonist

**Extends:** CharacterBody3D  
**Script:** `subsystems/colonists/colonist.gd`  
**Description:** Physical entity representing a colonist in the world. Owns HP state, carry inventory (`CharacterInventory`), equipment (`Equipment`, `EquipmentVisualizer`), skill set, labor priorities, and attached components (`ColonistBrain`, `ColonistNeeds`, `BTPlayer`, `VoxelPathfinder`, `ColonistAnimationController`).

**Key Properties & Components:**
- `colonist_id`: Unique identifier (`String`), generated in `_ready`.
- `colonist_def`: `ColonistDef` resource configuring base stats (`@export`, defaults to `default_colonist.tres`).
- `labor_priorities`: Dictionary mapping `labor_id` -> priority weight (`0..5`).
- `inventory`: `CharacterInventory`, code-created in `_ready` (mirrors Player's scene-placed inventory).
- `equipment`: `Equipment`, resolved/created in `_ready` via `Equipment.ensure_on(self, equipment)` — see [Equipment](equipment.md).
- `hunger_component`: `HungerComponent`, resolved/created in `_ready` via `HungerComponent.ensure_on(self)` — see [Hunger](hunger.md).
- `skill_set`: `SkillSet`, scene child (`$SkillSet`), seeded from `colonist_def.starting_skills`.
- `stamina_component`: `StaminaComponent`, scene child (`$StaminaComponent`).
- `pathfinder`: `VoxelPathfinder`, scene child (`$VoxelPathfinder`).
- `needs` / `brain` / `bt_player`: `ColonistNeeds` / `ColonistBrain` / `BTPlayer` — each resolved via `get_node_or_null` in `_ready`, code-created and added as a child if the scene doesn't already have one (so hand-authored scenes can override, but `colonist.tscn` need not include them). `bt_player.behavior_tree` loads from `data/ai/trees/colonist_root.tres` when created.
- `interaction`: `InteractionComponent`, resolved or code-created the same way; rebuilt each time via `refresh_interaction_options()`.

### Class: ColonistBrain

**Extends:** Node  
**Script:** `subsystems/ai/colonist_brain.gd`  
**Description:** Utility AI goal arbitrator. Evaluates need deficits (`ColonistNeeds`) against response curves (`NeedDef.responsecurve`), applies spatial proximity decay penalties, applies action commitment inertia (`+0.30` bonus to active goal), and writes winning goals (`&"work"`, `&"eat"`, `&"rest"`, `&"recreation"`) to the LimboAI `Blackboard`.

### Class: ColonistNeeds

**Extends:** Node  
**Script:** `subsystems/ai/colonist_needs.gd`  
**Description:** Tracks individual colonist need levels (`hunger`, `rest`, `recreation`) on a `0.0` to `1.0` scale. Automatically loads `NeedDef` resources from `data/needs/`, decays need levels over time, and provides serialization for `SaveSystem`.

### Class: ColonistAnimationController

**Extends:** Node  
**Script:** `subsystems/colonists/colonist_animation_controller.gd`  
**Description:** Manages animation playback, blending locomotion states with interaction loops. Supports behavior tree animation overrides via `play_animation_override(anim_name)` and `clear_override()`. Animations resolve through the scene AnimationPlayer's `mixamo` library (`assets/mixamo/mixamo.res`); missing keys fall back (Sprint to Walk, otherwise Idle) with a one-time warning. `_setup_skeleton()` re-homes the BoneMap-retargeted model skeleton's unique name (`GeneralSkeleton`) to the colonist scene root so library tracks like `%GeneralSkeleton:Hips` bind at runtime.

### Class: ColonistMoodletVisualizer

**Extends:** Node3D  
**Script:** `subsystems/colonists/colonist_moodlet_visualizer.gd`  
**Description:** In-world 3D billboard visualizer mounted on `Colonist` (`colonist.tscn`). Periodically (every 0.25s) evaluates `colonist.get_active_moodlets()` and displays the highest-priority active status icon on a `Sprite3D` billboard with distance culling (`visibility_range_end = 35.0`).

---

## Carry Inventory Hygiene & Equipment Fulfillment

There is no dedicated hygiene component — both concerns are driven from `BTActionClaimJob._cleanup_incompatible_held_items`, which runs on every job-claim boundary (and again from `JobBoard.get_best_job_for`'s idle fallback):

1. **Equipment Audit First**: `EquipmentAudit.run_audit(colonist, job_board)` reconciles the colonist's desired loadout (`Equipment._desired_slots`) before hygiene — swapping main_hand/holster and off_hand/back in place where possible, and posting a `FetchEquipmentJob` otherwise. See [Equipment](equipment.md).
2. **Tool Protection**: If the colonist's hands are full (`colonist.hands_full()`) and the current or upcoming job requires a specific tool tag, `colonist.equipment.has_required_equipment(...)` (falling back to an inventory tag scan) checks whether a matching tool is already held. If not, `colonist.drop_held_item()` drops one carried item to the ground to free a hand.
3. **Non-Tool Item Cleanup**: For hauling jobs where the colonist isn't standing at the destination crate/sink, `AIUtils.drop_unneeded_items(colonist, needed_ids)` drops every non-tool carried item whose `item_id` isn't in `needed_ids` (the job's still-required materials) as loose `WorldItem`s at the colonist's feet.
4. **No Batching, No Cooldown**: Items are dropped one at a time via `WorldItem.spawn_at`; there is no opportunistic multi-item gathering pass and no purge cooldown on the dropped items — a colonist can pick the same item back up on its next job evaluation. See [Inventory](inventory.md) for `WorldItem.forbidden`, the only supported "don't touch this" flag (player-toggled, not auto-set here).

---

## Moodlet System (`data/moodlets/`)

The Moodlet system allows data-driven evaluation and visual representation of colonist statuses (needs deficits, injuries, fatigue, stress):

- **`MoodletDef` (`data/moodlets/moodlet_def.gd`)**: Base Resource schema exporting `id`, `display_name`, `icons: Array[Texture2D]`, `@export var icon_hframes: Array[int] = []`, and `@export var line_number: int = 0` for multi-line vertical stacking. Provides virtual `evaluate_icon_index(entity) -> int` (< 0 for hidden, >= 0 for icon index), safe `get_active_texture(entity) -> Texture2D`, and `get_hframes(entity) -> int`.
- **`StatThresholdMoodletDef` (`data/moodlets/stat_threshold_moodlet_def.gd`)**: Generic threshold evaluator querying `colonist.get_stat_ratio(stat_id)` against ordered cutoff thresholds with `TriggerMode` (`BELOW_THRESHOLD` for depletion stats like HP/hunger/rest, `ABOVE_THRESHOLD` for accumulation stats). Inherits spritesheet animation support.
- **`ActivityMoodletDef` (`data/moodlets/activity_moodlet_def.gd`)**: Activity-driven evaluator mapping `colonist.get_current_activity()` identifiers (e.g. `&"idle"`, `&"mining"`, `&"eat"`, `&"rest"`) to icon array indices via `activity_icon_map`. Inherits spritesheet animation support.
- **`Colonist.moodlet_defs` (`data/colonists/colonist_def.gd`)**: Configures the list and display order of active moodlets on a per-archetype basis.
- **Unified Stat & Activity Getters**: `colonist.get_stat_ratio(stat_name)` (returns normalized 0.0 to 1.0 float), `colonist.get_stat_value(stat_name)` (returns raw numerical value), and `colonist.get_current_activity()` (returns current active behavior/labor `StringName`).
- **UI Integration**: Active moodlet icons are presented in the Colony Management roster (`ColonistEntry`) with tooltips and fixed aspect-ratio icon slots.
- **Visualizer Layout**: `ColonistMoodletVisualizer` arranges active moodlets grouped by `line_number` in compacted horizontal rows stacked vertically in 3D billboard space above the colonist's head (skipping inactive lines), dynamically syncing `Sprite3D.hframes` and advancing `Sprite3D.frame` for animated spritesheets at `frame_fps`.


---

## Pathfinding (`VoxelPathfinder` & Strategies)

**Pathfinder Node Script:** `subsystems/colonists/voxel_pathfinder.gd`  
**Strategy Package:** `subsystems/colonists/pathfinding/`

`VoxelPathfinder` coordinates 3D spatial voxel navigation (`+1` step climb, `-3` drop) with walkability predicates injected by `MapWiring`. Path calculation is decoupled into pluggable `PathfindingStrategy` implementations:

| Strategy | Script | Description |
| :--- | :--- | :--- |
| `SmoothedAStarStrategy` *(default)* | `smoothed_a_star_strategy.gd` | Combines 8-way stepped A* with Line-of-Sight (LOS) string pulling, collapsing collinear flat segments into direct straight paths across open ground while anchoring vertical steps and corner waypoints. |
| `AStar8WayStrategy` | `a_star_8_way_strategy.gd` | 8-directional horizontal expansion (cardinal + diagonal) with corner-cutting collision validation. |
| `AStar4WayStrategy` | `a_star_4_way_strategy.gd` | Classic 4-directional stepped orthogonal A* search. |
| `ThetaStarStrategy` | `theta_star_strategy.gd` | Any-angle Theta* search performing line-of-sight checks to parent nodes during open-set expansion. |

Strategies can be inspected or switched at runtime via `pathfinder.set_strategy(new_strategy)`. Telemetry (`last_query_start`, `last_query_target`, `last_status`, `last_explored_count`, `last_stand_candidates`, `last_query_time`) is exposed for visual diagnostics (`ColonistDebugVisualizer`).
