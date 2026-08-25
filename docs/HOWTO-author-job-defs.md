# HOWTO: Authoring Job Definitions (`JobDef`)

This guide explains how to create and configure data-driven job templates (`JobDef` resources) for colonist work in Vek: Holdout.

---

## Overview

A `JobDef` is a text-based Godot `.tres` Resource (`data/jobs/*.tres` extending `JobDef` in `data/jobs/job_def.gd`) that defines template rules for a category of work. When work is spawned at runtime (e.g. by blueprints, harvest commands, or crafting orders), a `JobInstance` is instantiated using a reference `JobDef`.

---

## Schema Properties (`JobDef`)

| Property Name | Type | Default | Description |
|---|---|---|---|
| `id` | `String` | `""` | Internal template identifier (e.g. `"construction"`, `"mining"`, `"hauling"`). |
| `display_name` | `String` | `""` | Human-readable label shown in UI and debug logs (e.g. `"Construction"`). |
| `labor_id` | `String` | `""` | The labor category ID matching colonist labor priorities (e.g. `"mining"`, `"hauling"`). |
| `required_tool_tag` | `StringName` | `&""` | Equipment tag required for this job (e.g. `&"pickaxe"`, `&"axe"`, `&"pruning_kit"`). |
| `work_animation` | `StringName` | `&"interact"` | Animation state played during work execution cycles (e.g. `&"digging"`, `&"hammering"`). |
| `work_duration` | `float` | `1.2` | Duration in seconds per work cycle/swing. |
| `default_units_per_cycle` | `int` | `20` | Default work units accomplished per swing cycle. |
| `base_priority` | `float` | `0.5` | Base score multiplier evaluated by Utility AI (`ColonistBrain`). |
| `max_assignees` | `int` | `1` | Maximum simultaneous worker claims allowed (`1` for single-colonist jobs like building; `>1` for divvied jobs like hauling). |
| `conditions` | `Array[Condition]` | `[]` | Optional array of actor condition resources (e.g. minimum skill requirements) evaluated before assignment. |
| `custom_subtree` | `BehaviorTree` | `null` | Optional LimboAI behavior tree override. If `null`, standard generic work BT is used. |

---

## Step-by-Step Creation Guide

### Method 1: In the Godot Editor

1. Open the FileSystem dock and navigate to `res://data/jobs/`.
2. Right-click and choose **Create New -> Resource...**.
3. Search for `JobDef` and click **Create**.
4. Save the file in `res://data/jobs/` using `snake_case` matching your job ID (e.g., `res://data/jobs/mining_job_def.tres`).
5. Select the file in the Inspector and populate the exported properties.

### Method 2: Manual Text Resource Creation

You can create `.tres` files directly in your text editor. Example for `construction_job_def.tres`:

```gdscript
[gd_resource type="Resource" script_class="JobDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/jobs/job_def.gd" id="1_jobdef"]

[resource]
script = ExtResource("1_jobdef")
id = "construction"
display_name = "Build Structure"
labor_id = "construction"
required_tool_tag = &"hammer"
work_animation = &"interact"
work_duration = 1.0
default_units_per_cycle = 25
base_priority = 0.8
max_assignees = 1
conditions = []
```

---

## Fractional Jobs & Multi-Worker Support

Setting `max_assignees > 1` allows multiple colonists to claim work units on the same `JobInstance` simultaneously.

- When a worker claims a job via `BTActionClaimJob`, `JobInstance.try_claim_units()` reserves a batch up to worker carrying capacity or remaining work units (`unclaimed_units`).
- If work is interrupted, `JobInstance.abandon_claim()` releases unworked units back into the pool for other colonists.
