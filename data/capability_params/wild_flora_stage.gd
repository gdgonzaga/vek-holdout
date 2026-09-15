class_name WildFloraStage
extends Resource
## Defines properties and yields for one growth stage of a wild plant or tree.

@export_range(0.0, 1.0) var min_progress: float = 0.0
@export var max_hp: int = 50

# --- Visuals ---
## Optional scene instantiated for this stage. If null, falls back to WildFloraDef.default_scene.
@export var scene: PackedScene = null

## Visual scale applied to the stage instance.
@export var visual_scale: Vector3 = Vector3.ONE

# --- Drops & Harvesting ---
## Whether this stage can be felled/removed at all (weapon damage or the
## colonist chop/removal job) — mirrors can_harvest_fruit so eligibility is
## authored per stage on both axes. Defaults true so existing content (every
## stage implicitly choppable today) is unaffected.
@export var can_chop: bool = true

## What drops when chopped down or destroyed with a weapon at this stage.
@export var fell_yields: Array[ItemAmount] = []

## Whether fruit or produce can be foraged without destroying the plant at this stage.
@export var can_harvest_fruit: bool = false

## What drops when foraged or picked at this stage.
@export var harvest_yields: Array[ItemAmount] = []
