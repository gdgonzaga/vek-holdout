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
+---------------+   +---------------+               +---------------+   +---------------+
(Utility AI)        (Hunger/Rest/Rec)               (LimboAI Engine)    (Voxel A* Path)
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

### Class: ColonistBrain

**Extends:** Node  
**Script:** `subsystems/ai/colonist_brain.gd`  
**Description:** Utility AI goal arbitrator. Evaluates need deficits (`ColonistNeeds`) against response curves (`NeedDef.response_curve`), applies spatial proximity decay penalties, applies action commitment inertia (`+0.30` bonus to active goal), and writes winning goals (`&"work"`, `&"eat"`, `&"rest"`, `&"recreation"`) to the LimboAI `Blackboard`.

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

## Pathfinding (`VoxelPathfinder`)

**Script:** `subsystems/colonists/voxel_pathfinder.gd`  
Voxel A* pathfinder operating with stepped 3D locomotion (`+1` climb, `-3` drop). Evaluates walkability predicates injected by `MapWiring`.
