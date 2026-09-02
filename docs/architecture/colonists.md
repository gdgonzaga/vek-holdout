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
see the class reference below and docs/HOWTO-use-makehuman-mixamo.md.)
```

---

## Core Classes

### Class: Colonist

**Extends:** CharacterBody3D  
**Script:** `subsystems/colonists/colonist.gd`  
**Description:** Physical entity representing a colonist in the world. Owns HP state, carry inventory, skill set, labor priorities, and attached components (`ColonistBrain`, `ColonistNeeds`, `BTPlayer`, `VoxelPathfinder`, `ColonistAnimationController`).

**Key Properties & Components:**
- `colonist_id`: Unique identifier (`String`).
- `colonist_def`: `ColonistDef` resource configuring base stats.
- `labor_priorities`: Dictionary mapping `labor_id` -> priority weight (`0..5`).
- `brain`: `@onready var brain: ColonistBrain = $ColonistBrain`
- `needs`: `@onready var needs: ColonistNeeds = $ColonistNeeds`
- `bt_player`: `@onready var bt_player: BTPlayer = $BTPlayer`
- `animation_controller`: `@onready var animation_controller = $ColonistAnimationController`
- `pathfinder`: `@onready var pathfinder: VoxelPathfinder = $VoxelPathfinder`

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
