# HOWTO: Authoring Need Definitions (`NeedDef`)

This guide explains how to author data-driven colonist need definitions (`NeedDef` resources) for the AI Subsystem in Xeno Frontier: Colony Defense.

---

## Overview

Colonist needs (e.g., Hunger, Rest, Recreation) are defined as text-based `.tres` Resource files in `data/needs/` using `NeedDef` (`data/schemas/need_def.gd`). The `ColonistNeeds` component dynamically loads all `.tres` files in `data/needs/` on startup, tracking decay and evaluating deficits for Utility AI decision-making.

---

## Schema Properties (`NeedDef`)

| Property Name | Type | Default | Description |
|---|---|---|---|
| `id` | `StringName` | `&"hunger"` | Unique identifier for the need (e.g. `&"hunger"`, `&"rest"`, `&"recreation"`). |
| `decay_per_game_hour` | `float` | `0.05` | Rate at which the need level decays from `1.0` (satisfied) toward `0.0` per second. |
| `response_curve` | `Curve` | `null` | Optional Godot inspector `Curve` mapping deficit (`0.0`..`1.0`) to Utility AI urgency score (`0.0`..`1.0`). If `null`, linear evaluation is used. |
| `emergency_threshold` | `float` | `0.10` | Critical need level threshold at which action commitment inertia is bypassed, forcing immediate need satisfaction. |
| `release_threshold` | `float` | `0.50` | Raw need level this need must recover to before `ColonistBrain` will release its hard lock on satisfying it. |
| `goal_name` | `StringName` | `&"eat"` | High-level goal identifier written to the agent's Blackboard when this need wins Utility arbitration (e.g. `&"eat"`, `&"rest"`, `&"recreation"`). |
| `target_group` | `StringName` | `&"storage_crate"` | Godot node group name for spatial proximity lookups of smart objects. The shipped needs use `&"storage_crate"` (hunger), `&"bed"` (rest) and `&"recreation_object"` (recreation) — the group name must match the furniture's `tags` entry exactly, or the need scores `0.0` forever. |
| `depletion_damage_interval` | `float` | `0.0` | Seconds between periodic damage ticks when need reaches 0.0 (`0.0` = no periodic damage). |
| `depletion_damage` | `int` | `0` | Hit points deducted per depletion damage tick. |
| `depletion_speed_mult` | `float` | `1.0` | Movement speed multiplier applied to the colonist while this need is fully depleted. |
| `depletion_stamina_mult` | `float` | `1.0` | Stamina recovery multiplier applied while this need is fully depleted. |

---

## Step-by-Step Creation Guide

### 1. File Location & Naming

All need definitions MUST be saved inside `res://data/needs/` with filenames matching `need_<id>.tres` (e.g., `data/needs/need_hunger.tres`, `data/needs/need_rest.tres`).

### 2. Example Resource (`need_hunger.tres`)

```gdscript
[gd_resource type="Resource" script_class="NeedDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/schemas/need_def.gd" id="1_needdef"]

[resource]
script = ExtResource("1_needdef")
id = &"hunger"
decay_per_game_hour = 0.005
emergency_threshold = 0.15
goal_name = &"eat"
target_group = &"storage_crate"
```

---

## Smart Object Group Integration

For `ColonistBrain` to locate smart objects (beds, dining chairs, entertainment stations):
1. Smart object nodes MUST register themselves into the corresponding Godot group (e.g. `add_to_group("bed")`) upon entering the scene tree.
2. Furniture nodes automatically register into designated groups during `_ready()` in `subsystems/furniture/furniture.gd`.
3. When `ColonistBrain` evaluates goals, it calculates spatial distance penalties based on the closest valid node in `target_group`.
