# HOWTO: Authoring Behavior Trees

This guide explains how to author and extend LimboAI Behavior Trees (`BehaviorTree`) and custom BT tasks for colonists and hostile agents in Vek: Holdout.

---

## Overview

Behavior Trees drive agent execution in the AI Subsystem (`subsystems/ai/`). Trees are stored as `.tres` resources in `data/ai/trees/` and evaluated by a `BTPlayer` node attached to character entities (`Colonist`, `EnemyBase`).

Decision-making is driven by a hybrid architecture:
- **Utility AI (`ColonistBrain`)**: Periodically evaluates needs and jobs to set high-level blackboard goals.
- **Behavior Tree (`BTPlayer`)**: Ticks the root behavior tree (`colonist_root.tres`) to execute action sequences matching the current blackboard goal.

---

## Behavior Tree Resources (`data/ai/trees/`)

| Tree Resource | Root Node | Purpose |
|---|---|---|
| `colonist_root.tres` | `BTDynamicSelector` | Master colonist behavior tree handling dynamic goal shifts between need satisfaction, work execution, and idle wandering. |
| `bt_generic_work.tres` | `BTSequence` | Generic job execution sequence (claim job -> verify tool -> navigate -> perform work). |
| `bt_haul_single_trip.tres` | `BTSequence` | Single-trip material transport sequence (claim -> navigate source -> pickup -> navigate target -> deposit). |
| `enemy_swarmer.tres` | `BTSelector` | Hostile swarmer tree executing voxel breaching, melee attacks, threat chasing, and scanning. |

---

## Custom BT Tasks (`subsystems/ai/tasks/`)

LimboAI tasks are implemented as GDScript classes extending `BTAction` or `BTCondition`.

### Creating a Custom Action Task

1. Create a script in `subsystems/ai/tasks/actions/` inheriting from `BTAction`.
2. Override `_generate_name()`, `_setup()`, `_enter()`, `_tick(delta)`, and `_exit()`.
3. Return status codes `SUCCESS`, `FAILURE`, or `RUNNING`.

Example structure:

```gdscript
@tool
extends BTAction
class_name BTActionCustomSample

@export var target_var: StringName = &"target_pos"

func _generate_name() -> String:
	return "CustomSample (%s)" % [target_var]

func _tick(delta: float) -> int:
	var target: Variant = blackboard.get_var(target_var)
	if target == null:
		return FAILURE
	# Execute logic...
	return SUCCESS
```

---

## Programmatic Tree Construction (`BTTreeFactory`)

For procedural generation or unit test sandboxes, use `BTTreeFactory` (`subsystems/ai/bt_tree_factory.gd`):

```gdscript
# Create and save a colonist root tree
var work_tree := BTTreeFactory.create_generic_work_tree()
var colonist_tree := BTTreeFactory.create_colonist_root_tree(work_tree)
ResourceSaver.save(colonist_tree, "res://data/ai/trees/colonist_root.tres")
```

---

## Authoring Trees in Godot Editor

1. Open the LimboAI bottom panel tab in the Godot Editor.
2. Load or create a new `BehaviorTree` resource in `res://data/ai/trees/`.
3. Use the visual graph editor to add compositors (`BTSelector`, `BTSequence`, `BTDynamicSelector`), decorators, and custom action/condition tasks from `subsystems/ai/tasks/`.
4. Edit Blackboard variables in the Inspector dock under **Blackboard Plan**.
