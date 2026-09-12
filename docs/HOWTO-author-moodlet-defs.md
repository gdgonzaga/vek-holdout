# HOWTO: Authoring Moodlet Definitions (`MoodletDef`)

This guide explains how to author data-driven moodlet definitions (`MoodletDef`, `StatThresholdMoodletDef`, and `ActivityMoodletDef` resources) for the Moodlet Subsystem in Xeno Frontier: Colony Defense.

---

## Overview

Moodlets provide visual status and activity feedback above colonists' heads in 3D billboard space (`ColonistMoodletVisualizer`). All moodlets are text-based `.tres` Resource files in `data/moodlets/` and attached to `ColonistDef.moodlet_defs`.

---

## Schema Types

### 1. `MoodletDef` (`data/moodlets/moodlet_def.gd`)
Base Resource schema for all moodlets.

| Property Name | Type | Default | Description |
|---|---|---|---|
| `id` | `StringName` | `&""` | Unique identifier for the moodlet (e.g. `&"hunger"`, `&"activity"`). |
| `display_name` | `String` | `""` | Human-readable label for UI tooltips. |
| `icons` | `Array[Texture2D]` | `[]` | Icon textures for active tiers or states. |
| `icon_hframes` | `Array[int]` | `[]` | Optional 1-to-1 array mapping each icon tier to its horizontal spritesheet frame count (defaults to `1` for static PNGs). |
| `frame_fps` | `float` | `6.0` | Default animation playback speed in frames per second (FPS) for animated spritesheets. |
| `icon_fps` | `Array[float]` | `[]` | Optional 1-to-1 array mapping each icon tier to a custom FPS override. |
| `line_number` | `int` | `0` | Vertical line/row index for multi-line layout (0 = bottom/primary line). Empty lines are skipped. |

---

### 2. `StatThresholdMoodletDef` (`data/moodlets/stat_threshold_moodlet_def.gd`)
Extends `MoodletDef`. Triggers moodlet tiers when colonist stats (HP, hunger, rest) cross threshold cutoffs.

| Property Name | Type | Default | Description |
|---|---|---|---|
| `stat_id` | `StringName` | `&"hunger"` | Stat ratio queried from `colonist.get_stat_ratio(stat_id)`. |
| `trigger_mode` | `TriggerMode` | `BELOW_THRESHOLD` | `BELOW_THRESHOLD` (depletion stats like HP/hunger) or `ABOVE_THRESHOLD` (accumulation stats like toxicity/stress). |
| `thresholds` | `Array[float]` | `[0.40, 0.15]` | Ordered cutoff thresholds evaluated from least to most severe. |

---

### 3. `ActivityMoodletDef` (`data/moodlets/activity_moodlet_def.gd`)
Extends `MoodletDef`. Maps `colonist.get_current_activity()` identifiers to icon array indices.

| Property Name | Type | Default | Description |
|---|---|---|---|
| `activity_icon_map` | `Dictionary` | `{}` | Key-value mapping of activity names (`&"idle"`, `&"mining"`, `&"construction"`, `&"crafting"`, `&"hauling"`, `&"eat"`, `&"rest"`) to icon array indices. |

---

## Step-by-Step Creation Guide

### 1. File Location & Naming
Save moodlet resources inside `res://data/moodlets/` with filenames matching `<id>_moodlet.tres` or `data/moodlets/<id>.tres` (e.g. `data/moodlets/activity_moodlet.tres`, `data/moodlets/hunger_moodlet.tres`).

### 2. Example Static / Animated Activity Resource (`activity_moodlet.tres`)

```tres
[gd_resource type="Resource" script_class="ActivityMoodletDef" format=3 uid="uid://dxgk7b3dp6hed"]

[ext_resource type="Script" path="res://data/moodlets/activity_moodlet_def.gd" id="1_script"]
[ext_resource type="Texture2D" path="res://assets/custom/activity_icons/idle.png" id="2_idle"]
[ext_resource type="Texture2D" path="res://assets/custom/activity_icons/mining.png" id="3_mining"]

[resource]
script = ExtResource("1_script")
id = &"activity"
display_name = "Current Activity"
icons = Array[Texture2D]([ExtResource("2_idle"), ExtResource("3_mining")])
icon_hframes = Array[int]([1, 4])
frame_fps = 8.0
activity_icon_map = {
  &"idle": 0,
  &"mining": 1,
  &"dig": 1
}
```

---

## Visualizer Layout & Camera Alignment

`ColonistMoodletVisualizer` and `EnemyMoodletVisualizer` handle in-world rendering:
- **Multi-Line Row Stacking**: Groups active moodlets by `line_number` and stacks rows vertically (`line_spacing = 0.35m`). Skips inactive lines so active rows remain cleanly compacted above the entity's head.
- **Multi-Sprite Row**: Displays active moodlets side-by-side in centered horizontal rows (`icon_spacing = 0.35m`).
- **Camera Alignment**: Aligns `global_rotation.y` with the active viewport camera so the icon rows always face the player's screen horizontally.
- **Spritesheet Animation**: Automatically advances `sprite.frame` at `frame_fps` for icons where `hframes > 1`.
