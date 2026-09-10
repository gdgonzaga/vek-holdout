# Subsystem: Colonists

The **Colonists** subsystem (`subsystems/colonists/`) manages colonist entity instances (`Colonist`), roster management via the `Colony` autoload singleton, utility goal selection (`ColonistBrain`), behavior tree execution (`BTPlayer`), dynamic needs (`ColonistNeeds`), and spatial voxel pathfinding (`VoxelPathfinder`).

---

## Component Architecture

```
                                  +-------------------+
                                  |     Colonist      |  (Entity root node)
                                  +---------+---------+
                                            |
        +-------------------+---------------+---------------+-------------------+---------------------+
        |                   |                               |                   |                     |
        v                   v                               v                   v                     v
+---------------+   +---------------+               +---------------+   +---------------+     +-------------------+
| ColonistBrain |   | ColonistNeeds |               |   BTPlayer    |   |VoxelPathfinder|     |ColonistItemManager|
+---------------+   +---------------+               +---------------+   +-------+-------+     +-------------------+
(Utility AI)        (Hunger/Rest/Rec)               (LimboAI Engine)            | delegates           (Pocket Hygiene &
                                                                                v                      Batch Gathering)
                                                                        +---------------+
                                                                        |Pathfinding-   |
                                                                        |Strategy       |
                                                                        +---------------+
                                                                        (4-Way, 8-Way,
                                                                         Smoothed, Theta*)

(Scene also mounts: ColonistAnimationController + AnimationPlayer [mixamo library] —
see the class reference below and docs/HOWTO-use-makehuman-mixamo.md. Also code-created in _ready:
CharacterInventory, Equipment, and EquipmentVisualizer — see docs/architecture/equipment.md.)
```

---

## Core Classes

### Class: Colonist

**Extends:** CharacterBody3D  
**Script:** `subsystems/colonists/colonist.gd`  
**Description:** Physical entity representing a colonist in the world. Owns HP state, carry inventory (`CharacterInventory`), equipment (`Equipment`, `EquipmentVisualizer`), skill set, labor priorities, and attached components (`ColonistBrain`, `ColonistNeeds`, `BTPlayer`, `VoxelPathfinder`, `ColonistAnimationController`).

**Key Properties & Components:**
- `colonist_id`: Unique identifier (`String`).
- `colonist_def`: `ColonistDef` resource configuring base stats.
- `labor_priorities`: Dictionary mapping `labor_id` -> priority weight (`0..5`).
- `inventory`: `var inventory: CharacterInventory` (carry inventory, code-created in `_ready`).
- `equipment`: `var equipment: Equipment` (8-slot equipment component, code-created in `_ready`).
- `brain`: `@onready var brain: ColonistBrain = $ColonistBrain`
- `needs`: `@onready var needs: ColonistNeeds = $ColonistNeeds`
- `bt_player`: `@onready var bt_player: BTPlayer = $BTPlayer`
- `animation_controller`: `@onready var animation_controller = $ColonistAnimationController`
- `pathfinder`: `@onready var pathfinder: VoxelPathfinder = $VoxelPathfinder`
- `item_manager`: `@onready var item_manager: ColonistItemManager = $ColonistItemManager`

### Class: ColonistItemManager

**Extends:** Node  
**Script:** `subsystems/colonists/colonist_item_manager.gd`  
**Description:** Component managing carried inventory hygiene and opportunistic multi-item gathering. Distinguishes loose materials from tools/equipped items, coordinates single-crate auto-deposits, handles ground purge fallbacks with cooldowns, and batches nearby collect jobs within a 12m radius up to carry weight and colony storage availability.

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

### Class: ColonistAI (Deprecated)

**Extends:** Node  
**Script:** `subsystems/colonists/colonist_ai.gd`  
**Status:** Deprecated. Superseded by `ColonistBrain` utility arbitration and LimboAI behavior trees (`data/ai/trees/colonist_root.tres`). Preserved for backward compatibility during legacy scene migration.

### Class: ColonistMoodletVisualizer

**Extends:** Node3D  
**Script:** `subsystems/colonists/colonist_moodlet_visualizer.gd`  
**Description:** In-world 3D billboard visualizer mounted on `Colonist` (`colonist.tscn`). Periodically (every 0.25s) evaluates `colonist.get_active_moodlets()` and displays the highest-priority active status icon on a `Sprite3D` billboard with distance culling (`visibility_range_end = 35.0`).

---

## Smart Pocket Management & Inventory Hygiene

`ColonistItemManager` enforces clean colonist pockets across all behavioral loops:

1. **Loose Item Identification**:
   - Any inventory item not currently equipped and lacking the `"tool"` item tag is treated as loose cargo.
2. **Opportunistic Multi-Item Gathering**:
   - Following the completion of a `CollectItemJob`, `ColonistItemManager` searches for other `CollectItemJob` candidates within `GATHER_RADIUS` (12m).
   - Candidates are collected in the same trip if they satisfy **both** remaining colonist weight capacity and `StorageRegistry.find_storage_for(item_id, colonist_pos) != null`. Can batch heterogeneous materials (e.g. 5 Wood + 2 Stone).
3. **Two-Tier Hygiene Execution**:
   - **Tier 1 (Single-Crate Deposit Loop)**: When loose materials are carried, the manager finds the nearest storage crate that can accept at least one held item and assigns an atomic `DepositItemJob`. Upon completion, if loose materials remain, the manager immediately selects the next capable crate.
   - **Tier 2 (Purge Drop Fallback)**: If no storage container in the colony can accept any remaining loose items, the colonist drops the items on the ground via `colonist.drop_item()`. Dropped `WorldItem`s receive a 20-second purge cooldown (`purge_cooldown_until_msec`), preventing immediate re-pickup loops.
4. **Behavior Tree Gating (`BTActionClaimJob`)**:
   - Prior to claiming unrelated labor (e.g. mining or building), `BTActionClaimJob` checks `item_manager.has_loose_items()`. If loose items exist, it runs hygiene to deposit or purge items before proceeding to the designated task.

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
