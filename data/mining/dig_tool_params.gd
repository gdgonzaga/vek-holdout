class_name DigToolParams
extends Resource
## Stats of the mining dig action (docs/TODO.md Phase 5). Authored as a data
## resource so the numbers live in data/ (hard rule 1) and a future equipped
## tool item (pickaxe) can reference or override the same bundle — DigAction
## reads whatever resource its trigger hands it, so the build-menu tool today
## and an equipped-tool LMB later share one code path.

enum Shape { BOX, SPHERE }

## Seconds one dig takes before hp/skill scaling. DigAction multiplies by the
## target material's hp / 100 (the def's break pool — terrain_mining/plan.md),
## then divides by the actor's mining skill multiplier (same seam
## HarvestAction uses for harvesting).
@export var work_time: float = 2.0

## Excavation shape: BOX (clean, flat walls/floors) or SPHERE (round excavation).
@export var shape: Shape = Shape.BOX

## Size of the carved box in world units (when shape == BOX).
@export var box_size: Vector3 = Vector3(1.0, 1.0, 1.0)

## Radius of the carved sphere (when shape == SPHERE).
@export var carve_radius: float = 1.5

## Snap target to integer grid coordinates for clean, aligned excavation.
@export var snap_grid: bool = true
