# HOWTO: Authoring Job Definitions (`JobDef`)

This guide explains how to create and configure data-driven job templates (`JobDef` resources) for colonist work in Xeno Frontier: Colony Defense.

---

## Overview

A `JobDef` is a text-based Godot `.tres` Resource (`data/jobs/*.tres` extending `JobDef` in `data/jobs/job_def.gd`) that defines template rules for a category of work. At runtime a def backs one of two job forms — a legacy `Job` (what Colony's producers spawn for blueprints, harvest marks, farming, crafting orders, and dig designations) or a fractional `JobInstance` — and both are driven through the same LimboAI work tree (claim -> verify tool -> navigate -> perform work), with the def supplying the behavior.

---

## Schema Properties (`JobDef`)

| Property Name | Type | Default | Description |
|---|---|---|---|
| `id` | `String` | `""` | Internal template identifier (e.g. `"construction"`, `"mining"`, `"hauling"`). |
| `display_name` | `String` | `""` | Human-readable label shown in UI and debug logs (e.g. `"Construction"`). |
| `labor_id` | `String` | `""` | The labor category ID matching colonist labor priorities (e.g. `"mining"`, `"hauling"`). |
| `required_equipped` | `String` | `""` | Specific required item ID equipped for this job (e.g. `"laser_drill"`). |
| `required_equipped_tags` | `Array[StringName]` | `[]` | Equipment tags required for this job (e.g. `[&"mining_tool"]`, `[&"construction_tool"]`). |
| `work_animation` | `StringName` | `&"Interact"` | Animation played during work execution cycles. Must match a key in the shared mixamo AnimationLibrary (`assets/mixamo/mixamo.res`) exactly, case included — currently `Idle`, `Walk`, `Jump`, `Digging`, `Interact` (see `docs/HOWTO-use-makehuman-mixamo.md`). Unknown keys warn once and fall back (`Sprint`→`Walk`, else `Idle`). |
| `work_duration` | `float` | `1.2` | Duration in seconds per work cycle/swing, before the worker's skill multiplier. Author `0.0` for dynamic-duration labors — the def's `begin(actor, job)` then supplies the per-target duration (construction's `build_time`, crafting's recipe `base_time`, crop-driven harvest). |
| `default_units_per_cycle` | `int` | `20` | Default work units accomplished per swing cycle. |
| `base_priority` | `float` | `0.5` | Base score multiplier evaluated by Utility AI (`ColonistBrain`). |
| `max_assignees` | `int` | `1` | Maximum simultaneous worker claims allowed (`1` for single-colonist jobs like building; `>1` for divvied jobs like hauling). |
| `conditions` | `Array[Condition]` | `[]` | Optional array of actor condition resources (e.g. minimum skill requirements) evaluated before assignment. |
| `custom_subtree` | `BehaviorTree` | `null` | Optional LimboAI behavior tree override. If `null`, standard generic work BT is used. |
| `requires_adjacent` | `bool` | `true` | Whether the colonist must navigate to a cell adjacent to the target (mining/building) rather than stand directly on it (deploy/stationing). |

---

## Script-Side Behavior (Virtuals)

The `.tres` covers the data half; the behavior half is a set of virtuals on `JobDef` (base defaults in `data/jobs/job_def.gd`, full contract table in ARCH Jobs). A plain `JobDef` resource with no subclass already works: one work cycle ends the job (skill XP recorded, job dropped from the board). You need a subclass script when the labor has a real world effect or non-trivial lifetime:

- **`complete(actor, job)`** — the terminal effect of a work cycle (carve the voxel, materialize the blueprint, resolve the harvest). Apply the effect, then call `_finish(actor, job)` to record XP and drop the job; skip `_finish` for looping labors (hauling cycles never terminally complete).
- **`begin(actor, job)`** — per-target duration in unskilled seconds; only consulted when `work_duration` is `0.0`.
- **`is_available(job)` / `should_close(job)`** — claimability and board lifetime. Override to drought-wait (hauling stays registered but unclaimable until a crate restocks) or to hide work whose target stopped needing it (an unmarked harvest, an unoccupied-again blueprint).
- **`on_abort(actor, job, elapsed)`** — a need preempted the work cycle mid-animation: persist partial progress, release claims.
- **`work_site(actor, job)`** — per-cycle walk target for multi-site labors (hauling: crate while empty-handed, sink while carrying); `null` uses the job's anchor/target placement.
- **`_needs(growable)` / `_apply(growable, actor)`** — the farming skeleton (`FarmingJobDef`): a new farm labor drops in by overriding just these two.

Existing def subclasses (`data/jobs/*_job_def.gd`) are the reference implementations — `dig_job_def.gd` is the minimal `complete()` + gates example.

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
required_equipped_tags = Array[StringName]([&"construction_tool"])
work_animation = &"Interact"
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

---

## Tool Tag Discipline & Requirements

Jobs that require specific tools declare them via the `required_equipped_tags` property:

```gdscript
required_equipped_tags = Array[StringName]([&"mining_tool"])
```

> [!IMPORTANT]
> **Do NOT use `conditions` for required tools.**
> Def-level `conditions` check colonist capabilities prior to job selection. Putting a tool condition there would mean a toolless worker can never claim the job to go fetch the tool from storage. The universal work tree and `JobBoard` check `required_equipped_tags` and handle fetching automatically.

---

## Authoring Multi-Step Pipelines (`JobSequenceDef`)

When a gameplay task requires multiple distinct stages (e.g. Haul materials to site, then Build structure), create a `JobSequenceDef` subclass (`data/jobs/*_sequence_def.gd`):

1. Extend `JobSequenceDef` (`data/jobs/job_sequence_def.gd`).
2. Override `_build_steps(sequence: JobSequence, target: Node, anchor: Vector3i) -> void`:
   - Inspect target state (e.g. `MaterialSink.needed_item_ids()`).
   - Create step jobs (`Job.from_def(...)`), bind `job.sequence_id = sequence.id`, register on `JobBoard.add_job()`, and append to `sequence.add_step(job.id)`.
3. The board handles linear step unlocking, pruning protection for pending steps, and cascading cancellation automatically.

---

## Authoring Hauling Defs (`HaulingJobDef`)

General material and item transport uses a single looping def, `HaulingJobDef` (`data/jobs/hauling_job_def.gd`), rather than separate atomic collect/deposit jobs. It branches on what `job.target_node` resolves to:

- **Storage crate target** (a `Furniture` with a `StorageInventory`) — one-shot deposit of everything the colonist is carrying, then finishes.
- **`MaterialSink` target** (a blueprint or crafting station) — loops fetch/deliver cycles via `work_site` (crate while empty-handed, sink while carrying a needed material) until `sink.has_complete_materials()`; drought-persistent (unclaimable via `is_available`/`is_available_for` while no crate stocks a needed material, but stays registered).
- **`WorldItem` target** (a dropped item on the ground) — picks the item up, opportunistically gathers nearby same-`item_id` items within `GATHER_SEARCH_RADIUS` (12m) while carry capacity allows, then delivers to the nearest crate with space via `StorageRegistry.find_storage_for` (falling back to `nearest_crate`).

Author one `.tres` (e.g. `res://data/jobs/hauling.tres`) with `labor_id = "hauling"`; the target-node branching happens entirely in script, not via separate defs. See `docs/architecture/jobs.md#ground-item-hauling-haulingjobdef-targeting-a-worlditem` for the full flow trace.
